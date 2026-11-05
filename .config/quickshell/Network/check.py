#!/usr/bin/env python3
"""Explicit, read-only connection diagnostics. No work is performed on import."""
from __future__ import annotations
import datetime
import http.client
import ipaddress
import json
import os
import signal
import socket
import ssl
import subprocess
import sys
import threading
import time

HOSTS = {'cloudflare': 'speed.cloudflare.com', 'arch': 'ping.archlinux.org'}
TITLES = {'link': 'Network link', 'router': 'Router', 'dns': 'DNS', 'internet': 'Internet'}
LIMIT = 256 * 1024

class Cancelled(Exception): pass
class CheckError(Exception): pass


def clean_interface(value):
    return value if isinstance(value, str) and 0 < len(value.encode()) <= 15 and not value.startswith('-') and all(c.isalnum() or c in '_.:-' for c in value) else None


def valid_ip(value):
    try:
        item = ipaddress.ip_address(value)
        return str(item) if not item.is_unspecified and not item.is_multicast and not item.is_loopback else None
    except (TypeError, ValueError):
        return None


def network_info(addresses, routes4, routes6, policy4, policy6):
    """Main routes describe the local router, not necessarily the VPN egress."""
    links = []
    for item in addresses:
        name = clean_interface(item.get('ifname'))
        flags = item.get('flags', [])
        if not name or name == 'lo' or 'UP' not in flags or item.get('operstate') in ('DOWN', 'LOWERLAYERDOWN', 'NOTPRESENT'):
            continue
        usable = []
        for entry in item.get('addr_info', []):
            value = valid_ip(entry.get('local'))
            if value and not ipaddress.ip_address(value).is_link_local and not entry.get('tentative') and not entry.get('dadfailed'):
                usable.append(value)
        if usable:
            links.append({'name': name, 'addresses': usable})
    names = {item['name'] for item in links}
    candidates = []
    for route in routes4 + routes6:
        name = clean_interface(route.get('dev'))
        gateway = valid_ip(route.get('gateway'))
        if name in names and gateway and route.get('type', 'unicast') == 'unicast':
            candidates.append((int(route.get('metric', 0)), name, gateway))
    candidates.sort()
    policies = [item for item in policy4 + policy6 if clean_interface(item.get('dev')) and item.get('type', 'unicast') == 'unicast']
    return {'links': links, 'router': candidates[0][1:] if candidates else None,
            'policyDevices': sorted({item['dev'] for item in policies})}


class Owner:
    """Only known children are terminated; never process groups or user services."""
    def __init__(self, cancelled=None, clock=time.monotonic, seconds=15):
        self.cancelled = cancelled or threading.Event()
        self.clock = clock
        self.deadline = clock() + seconds
        self.children = set()

    def check(self):
        if self.cancelled.is_set(): raise Cancelled()
        if self.clock() >= self.deadline: raise CheckError('The check timed out. Try again when the connection has settled.')

    @staticmethod
    def stop(child):
        if child.poll() is None:
            try:
                child.terminate()
                try: child.wait(timeout=0.15)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=0.3)
            except ProcessLookupError:
                child.wait(timeout=0.3)
        if child.stdout is not None:
            child.stdout.close()

    def run(self, arguments, seconds):
        self.check()
        deadline = min(self.deadline, self.clock() + seconds)
        try:
            child = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, env=dict(os.environ, LC_ALL='C'))
        except OSError as error:
            raise CheckError('A required diagnostic tool could not start.') from error
        self.children.add(child)
        try:
            while True:
                self.check()
                remaining = deadline - self.clock()
                if remaining <= 0: raise TimeoutError()
                try:
                    output, _ = child.communicate(timeout=min(0.05, remaining))
                    if len(output) > LIMIT: raise CheckError('The diagnostic response was too large.')
                    return child.returncode, output.decode('utf-8', errors='replace')
                except subprocess.TimeoutExpired:
                    pass
        finally:
            self.stop(child)
            self.children.discard(child)

    def close(self):
        for child in list(self.children): self.stop(child)
        self.children.clear()


class Probes:
    def __init__(self, owner):
        self.owner = owner
        self.script = os.path.abspath(__file__)

    def json_command(self, arguments, seconds=0.65):
        try:
            code, text = self.owner.run(arguments, seconds)
            result = json.loads(text)
            return result if code == 0 and isinstance(result, list) else []
        except (TimeoutError, ValueError, CheckError):
            self.owner.check()
            return []

    def local(self):
        addresses = self.json_command(['ip', '-j', 'address', 'show'])
        if not addresses:
            raise CheckError('Network adapters could not be inspected. Please try again.')
        routes4 = self.json_command(['ip', '-j', '-4', 'route', 'show', 'default'])
        routes6 = self.json_command(['ip', '-j', '-6', 'route', 'show', 'default'])
        policy4 = self.json_command(['ip', '-j', '-4', 'route', 'get', '1.1.1.1', 'ipproto', 'tcp', 'dport', '443'])
        policy6 = self.json_command(['ip', '-j', '-6', 'route', 'get', '2606:4700:4700::1111', 'ipproto', 'tcp', 'dport', '443'])
        return network_info(addresses, routes4, routes6, policy4, policy6)

    def child(self, mode, name='', addresses=None, seconds=3):
        arguments = [sys.executable, self.script, mode]
        if name: arguments.append(name)
        if addresses is not None: arguments.append(json.dumps(addresses, separators=(',', ':')))
        try:
            code, text = self.owner.run(arguments, seconds)
            value = json.loads(text)
            return value if code == 0 and isinstance(value, dict) else {'ok': False, 'error': 'unavailable'}
        except (TimeoutError, ValueError):
            return {'ok': False, 'error': 'timeout'}

    def router(self, name, gateway):
        if not clean_interface(name) or not valid_ip(gateway): return False
        try:
            code, _ = self.owner.run(['ping', '-6' if ':' in gateway else '-4', '-n', '-q', '-c', '1', '-W', '1', '-w', '2', '-I', name, gateway], 2)
            return code == 0
        except (TimeoutError, CheckError):
            self.owner.check()
            return False


def resolved_addresses(name):
    result = []
    for family, kind, proto, canonical, address in socket.getaddrinfo(HOSTS[name], 443 if name == 'cloudflare' else 80, type=socket.SOCK_STREAM):
        value = valid_ip(address[0])
        if value and value not in result: result.append(value)
    return {'ok': bool(result), 'addresses': result[:8]}


def probe_http(name, addresses):
    """Direct validated-IP socket: no hidden second, unbounded getaddrinfo call."""
    secure = name == 'cloudflare'
    host = HOSTS[name]
    port = 443 if secure else 80
    path = '/__down?bytes=0' if secure else '/nm-check.txt'
    candidates = []
    # Try one address per family first, so an unusable IPv6 route has a v4 fallback.
    for version in (4, 6):
        candidate = next((value for value in addresses if valid_ip(value) and ipaddress.ip_address(value).version == version), None)
        if candidate: candidates.append(candidate)
    error = 'connection'
    for value in candidates:
        connection = None
        stream = None
        try:
            family = socket.AF_INET6 if ':' in value else socket.AF_INET
            stream = socket.socket(family, socket.SOCK_STREAM)
            stream.settimeout(0.9)
            stream.connect((value, port))
            if secure:
                stream = ssl.create_default_context().wrap_socket(stream, server_hostname=host)
            connection = http.client.HTTPConnection(host, port, timeout=0.9)
            connection.sock = stream
            connection.request('GET', path, headers={'User-Agent': 'Quickshell-ConnectionCheck/1.0', 'Connection': 'close', 'Accept-Encoding': 'identity', 'Cache-Control': 'no-cache'})
            response = connection.getresponse()
            body = response.read(1025)
            expected = (response.status in (200, 204) and not body) if secure else (response.status == 200 and len(body) <= 1024 and (response.getheader('X-NetworkManager-Status', '').lower() == 'online' or body.startswith(b'NetworkManager is online')))
            return {'ok': bool(expected), 'status': response.status,
                    'redirect': 300 <= response.status < 400, 'unexpected': not expected,
                    'oversize': len(body) > 1024, 'error': ''}
        except ssl.SSLError:
            error = 'tls'
        except (OSError, http.client.HTTPException, ValueError):
            error = 'connection'
        finally:
            if connection is not None: connection.close()
            elif stream is not None: stream.close()
    return {'ok': False, 'error': error}


def probe_tcp():
    for value in ('1.1.1.1', '2606:4700:4700::1111'):
        stream = socket.socket(socket.AF_INET6 if ':' in value else socket.AF_INET, socket.SOCK_STREAM)
        try:
            stream.settimeout(0.65)
            stream.connect((value, 443))
            return {'ok': True}
        except OSError: pass
        finally: stream.close()
    return {'ok': False}


def summarize(steps, secure, portal, direct):
    states = {item['id']: item['status'] for item in steps}
    if states['link'] == 'failed':
        return {'status': 'failed', 'title': 'No usable network link', 'detail': 'Connect to Wi-Fi or Ethernet, or wait for an IP address.'}
    if secure.get('ok'):
        if portal.get('redirect') or portal.get('unexpected'):
            return {'status': 'warning', 'title': 'Secure internet works', 'detail': 'The plain web check was redirected or filtered. Some access may require sign-in.'}
        detail = 'DNS and secure web access work.'
        if states['router'] == 'warning': detail += ' Your router may simply block ping.'
        return {'status': 'ok', 'title': "You’re online", 'detail': detail}
    if portal.get('ok'):
        detail = 'The Arch web check works, but another test name could not resolve. DNS filtering or partial name resolution may be involved.' if states['dns'] == 'failed' else 'Plain web access works, but the secure test failed. A filter, TLS issue or test service may be involved.'
        return {'status': 'warning', 'title': 'Web access partly works', 'detail': detail}
    if portal.get('redirect') or portal.get('unexpected'):
        return {'status': 'warning', 'title': 'A sign-in page may be required', 'detail': 'The web check was redirected or filtered. Open a website in your browser to check for network sign-in.'}
    if states['dns'] == 'failed':
        return {'status': 'warning', 'title': 'DNS may be the problem' if direct.get('ok') else 'Connection not confirmed',
                'detail': 'A direct IP connection works, but the test name could not be resolved.' if direct.get('ok') else 'The test name and direct endpoint could not be reached. Check the network, VPN or proxy; this does not prove every site is offline.'}
    return {'status': 'warning', 'title': 'Internet access not confirmed', 'detail': 'DNS works, but the test sites did not answer as expected. Check the router, VPN, proxy or network filter, then retry.'}


class Runner:
    def __init__(self, output=None, owner=None, probes=None, clock=time.monotonic):
        self.owner = owner or Owner(clock=clock)
        self.probes = probes or Probes(self.owner)
        self.clock = clock
        self.output = output or (lambda value: print(json.dumps(value, ensure_ascii=False, allow_nan=False), flush=True))
        self.snapshot = {'phase': 'running', 'steps': [{'id': name, 'status': 'pending', 'title': title, 'detail': 'Waiting…', 'durationMs': None} for name, title in TITLES.items()], 'summary': {'status': 'idle', 'title': 'Checking your connection', 'detail': 'A few small checks, without changing any settings.'}, 'checkedAt': None}

    def emit(self):
        self.output(json.loads(json.dumps(self.snapshot, allow_nan=False)))

    def step(self, name, status, detail, started=None):
        item = next(item for item in self.snapshot['steps'] if item['id'] == name)
        item.update(status=status, detail=detail, durationMs=round(max(0, self.clock() - started) * 1000, 1) if started is not None else None)
        self.emit()

    def run(self):
        try:
            self.emit()
            started = self.clock(); self.step('link', 'running', 'Checking adapters and IP addresses…')
            info = self.probes.local(); self.owner.check()
            if not info['links']:
                self.step('link', 'failed', 'No active adapter has a usable IP address.', started)
                for name in ('router', 'dns', 'internet'): self.step(name, 'skipped', 'Connect to a network first.')
                summary = summarize(self.snapshot['steps'], {}, {}, {})
            else:
                names = ', '.join(item['name'] for item in info['links'][:3])
                self.step('link', 'ok', 'Connected with an IP address · ' + names, started)
                started = self.clock(); self.step('router', 'running', 'Checking the local gateway…')
                router = info['router']
                if router:
                    reply = self.probes.router(*router); self.owner.check()
                    self.step('router', 'ok' if reply else 'warning', 'Your local gateway replies.' if reply else 'No ping reply. Routers can block ping; the internet check continues.', started)
                else:
                    self.step('router', 'skipped', 'No local gateway address to ping. VPN and point-to-point routes can be valid.', started)
                started = self.clock(); self.step('dns', 'running', 'Resolving a public test name…')
                dns = self.probes.child('--resolve', 'cloudflare', seconds=3); self.owner.check()
                addresses = dns.get('addresses', []) if dns.get('ok') else []
                self.step('dns', 'ok' if addresses else 'failed', 'The system resolver answers for the test name.' if addresses else 'The test name could not be resolved. This may be DNS or a wider network issue.', started)
                started = self.clock(); self.step('internet', 'running', 'Checking secure web access…')
                secure = self.probes.child('--probe', 'cloudflare', addresses, seconds=3) if addresses else {'ok': False}
                self.owner.check()
                direct = self.probes.child('--tcp', seconds=1.6) if not addresses else {}
                self.owner.check()
                arch_dns = self.probes.child('--resolve', 'arch', seconds=1.3)
                portal = self.probes.child('--probe', 'arch', arch_dns.get('addresses', []), seconds=2) if arch_dns.get('ok') else {'ok': False}
                self.owner.check()
                if secure.get('ok'):
                    detail = 'A verified HTTPS connection reached the test service.'
                    status = 'ok'
                elif direct.get('ok'):
                    detail = 'A direct IP connection works; web names are still unavailable.'; status = 'warning'
                elif portal.get('ok'):
                    detail = 'Plain web access works, but the secure probe did not succeed.'; status = 'warning'
                elif portal.get('redirect') or portal.get('unexpected'):
                    detail = 'The web check was redirected or filtered. A network sign-in may be needed.'; status = 'warning'
                else:
                    detail = 'The test service could not be reached. A filter, VPN, proxy or service issue is also possible.'; status = 'warning'
                self.step('internet', status, detail, started)
                summary = summarize(self.snapshot['steps'], secure, portal, direct)
            self.snapshot.update(phase='complete', summary=summary, checkedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
            self.emit()
            return 0
        except Cancelled:
            self.snapshot.update(phase='cancelled', summary={'status': 'cancelled', 'title': 'Check cancelled', 'detail': 'No network settings were changed.'})
            return self.finish_pending('Check cancelled.', 0)
        except (CheckError, OSError, ValueError, TypeError, KeyError) as error:
            self.snapshot.update(phase='error', summary={'status': 'error', 'title': 'Check could not finish', 'detail': str(error) if isinstance(error, CheckError) else 'Diagnostic information was unavailable. Please try again.'})
            return self.finish_pending('Check did not finish.', 1)
        finally:
            self.owner.close()

    def finish_pending(self, detail, code):
        for item in self.snapshot['steps']:
            if item['status'] in ('pending', 'running'): item.update(status='skipped', detail=detail)
        self.snapshot['checkedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        self.emit()
        return code


def main():
    # Internal bounded child modes; only fixed hosts and validated IPs are accepted.
    if len(sys.argv) == 3 and sys.argv[1] == '--resolve' and sys.argv[2] in HOSTS:
        try: value = resolved_addresses(sys.argv[2])
        except (OSError, ValueError): value = {'ok': False, 'addresses': []}
    elif len(sys.argv) == 4 and sys.argv[1] == '--probe' and sys.argv[2] in HOSTS:
        try:
            addresses = json.loads(sys.argv[3])
            if not isinstance(addresses, list) or len(addresses) > 8 or not all(isinstance(value, str) and valid_ip(value) for value in addresses): raise ValueError()
            value = probe_http(sys.argv[2], addresses)
        except (OSError, ValueError): value = {'ok': False, 'error': 'unavailable'}
    elif sys.argv[1:] == ['--tcp']:
        value = probe_tcp()
    elif not sys.argv[1:]:
        owner = Owner()
        signal.signal(signal.SIGTERM, lambda *_: owner.cancelled.set())
        signal.signal(signal.SIGINT, lambda *_: owner.cancelled.set())
        return Runner(owner=owner).run()
    else:
        raise SystemExit('Usage: check.py')
    print(json.dumps(value, allow_nan=False), flush=True)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
