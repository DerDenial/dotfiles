#!/usr/bin/env python3
"""On-demand, read-only physical-interface telemetry. No network probes.

Linux interface byte counters are sampled using monotonic time. This measures
traffic on a Wi-Fi/Ethernet link, including local traffic and VPN transport;
it is not an Internet speed test and never adds VPN counters to the underlay.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import math
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


def read(path, default=''):
    try:
        with Path(path).open(encoding='utf-8', errors='replace') as stream:
            return stream.read(256 * 1024).strip()
    except OSError:
        return default


def counter(path):
    try:
        result = int(read(path))
        return result if 0 <= result <= 0xffffffffffffffff else None
    except ValueError:
        return None


def address_query(name):
    """Local netlink inspection only; no packets or name lookups are sent."""
    try:
        result = subprocess.run(['ip', '-j', 'address', 'show', 'dev', name],
                                capture_output=True, text=True, timeout=1)
        if result.returncode == 0 and len(result.stdout) <= 256 * 1024:
            value = json.loads(result.stdout)
            return value if isinstance(value, list) else []
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return []


class Telemetry:
    def __init__(self, proc='/proc', sysroot='/sys', clock=None, wallclock=None, query=None):
        self.proc = Path(proc)
        self.sys = Path(sysroot)
        self.clock = clock or time.monotonic
        self.wallclock = wallclock or time.time
        self.query = query or address_query
        self.previous = None
        self.baseline = None
        self.session_started = None
        self.address_id = None
        self.address_time = None
        self.addresses = ([], [])

    def interfaces(self):
        result = {}
        for folder in sorted((self.sys / 'class/net').glob('*')):
            # A backing device excludes loopback, VPN/tun, bridge/veth and other
            # virtual transports. Counting those as well would double traffic.
            if (not (folder / 'device').exists() or (folder / 'tun_flags').exists()
                    or read(folder / 'type') != '1'):
                continue
            name = folder.name
            if len(name.encode()) > 15 or any(ord(char) < 32 for char in name):
                continue
            state = read(folder / 'operstate')
            carrier = read(folder / 'carrier')
            connected = state not in ('down', 'lowerlayerdown', 'notpresent') and (
                carrier == '1' or not carrier and state == 'up')
            kind = 'wifi' if (folder / 'wireless').is_dir() or (folder / 'phy80211').exists() else 'ethernet'
            index = read(folder / 'ifindex')
            result[name] = {'name': name, 'id': name + ':' + (index or 'unknown'),
                            'kind': kind, 'connected': bool(connected), 'folder': folder}
        return result

    def default_routes(self, interfaces):
        routes = []
        for line in read(self.proc / 'net/route').splitlines()[1:]:
            fields = line.split()
            if len(fields) < 8 or fields[0] not in interfaces:
                continue
            try:
                flags, metric = int(fields[3], 16), int(fields[6])
                default = fields[1] == '00000000' and fields[7] == '00000000'
                if default and flags & 1 and not flags & 0x200:
                    routes.append((metric, 4, fields[0]))
            except ValueError:
                continue
        for line in read(self.proc / 'net/ipv6_route').splitlines():
            fields = line.split()
            if len(fields) < 10 or fields[9] not in interfaces:
                continue
            try:
                flags, metric = int(fields[8], 16), int(fields[5], 16)
                default = fields[0] == '0' * 32 and fields[1] == '00'
                if default and flags & 1 and not flags & 0x200:
                    routes.append((metric, 6, fields[9]))
            except ValueError:
                continue
        return sorted(route for route in routes if interfaces[route[2]]['connected'])

    def addresses_for(self, interface, now):
        if not interface['connected']:
            self.address_id = None
            self.address_time = None
            self.addresses = ([], [])
            return self.addresses
        if (interface['id'] != self.address_id or self.address_time is None
                or now - self.address_time >= 30 or now < self.address_time):
            ipv4, ipv6 = [], []
            reply = self.query(interface['name'])
            for item in reply if isinstance(reply, list) else []:
                if not isinstance(item, dict) or item.get('ifname', interface['name']) != interface['name']:
                    continue
                values = item.get('addr_info', [])
                for address in values if isinstance(values, list) else []:
                    if not isinstance(address, dict) or address.get('scope') not in ('global', 'link'):
                        continue
                    if any(address.get(flag) for flag in ('tentative', 'dadfailed')):
                        continue
                    try:
                        value = ipaddress.ip_address(address.get('local', ''))
                    except ValueError:
                        continue
                    if value.is_loopback or value.is_unspecified or value.is_multicast:
                        continue
                    target = ipv4 if value.version == 4 else ipv6
                    if str(value) not in target:
                        target.append(str(value))
            self.addresses = (ipv4[:8], ipv6[:8])
            self.address_id, self.address_time = interface['id'], now
        return self.addresses

    def reset(self):
        self.previous = None
        self.baseline = None
        self.session_started = None

    def sample(self):
        interfaces = self.interfaces()
        routes = self.default_routes(interfaces)
        connected = [item for item in interfaces.values() if item['connected']]
        selected = (interfaces[routes[0][2]] if routes else connected[0] if connected
                    else next(iter(interfaces.values()), None))
        warnings = []
        interface = {'id': '', 'name': '', 'kind': 'none', 'connected': False,
                     'ipv4': [], 'ipv6': [], 'defaultRoute': False}
        now = self.clock()
        if selected:
            interface.update({key: selected[key] for key in ('id', 'name', 'kind', 'connected')})
            interface['defaultRoute'] = bool(routes)
            interface['ipv4'], interface['ipv6'] = self.addresses_for(selected, now)
            if selected['connected'] and not routes:
                warnings.append("No physical default route was found; showing this link's traffic.")
            if len({route[2] for route in routes}) > 1:
                warnings.append('Several links have default routes; only the selected physical link is shown.')
        else:
            self.address_id = None
            self.address_time = None
            self.addresses = ([], [])
        rx = counter(selected['folder'] / 'statistics/rx_bytes') if selected and selected['connected'] else None
        tx = counter(selected['folder'] / 'statistics/tx_bytes') if selected and selected['connected'] else None
        # Timestamp the counter pair after any occasional metadata query.
        now = self.clock()
        download = upload = elapsed = received = sent = None
        if rx is None or tx is None:
            if selected and selected['connected']:
                warnings.append('Traffic counters are temporarily unavailable.')
            self.reset()
        else:
            previous = self.previous
            identity = interface['id']
            if previous and previous[0] == identity:
                elapsed = now - previous[1]
                if elapsed <= 0 or elapsed > 10 or rx < previous[2] or tx < previous[3]:
                    self.reset()
                    elapsed = None
                else:
                    download, upload = (rx - previous[2]) / elapsed, (tx - previous[3]) / elapsed
            else:
                self.reset()
            if self.baseline is None:
                self.baseline = (rx, tx)
                self.session_started = now
            received, sent = rx - self.baseline[0], tx - self.baseline[1]
            self.previous = (identity, now, rx, tx)
        return {'ok': True, 'timestamp': self.wallclock(), 'monotonic': now,
                'interface': interface,
                'rxBytesPerSecond': round(download, 2) if download is not None else None,
                'txBytesPerSecond': round(upload, 2) if upload is not None else None,
                'receivedBytes': received, 'sentBytes': sent,
                'sampleSeconds': round(elapsed, 4) if elapsed is not None else None,
                'sessionStarted': self.session_started, 'warnings': warnings}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--stream', action='store_true')
    mode.add_argument('--once', action='store_true')
    parser.add_argument('--interval', type=float, default=1.0)
    args = parser.parse_args()
    if not math.isfinite(args.interval) or not 0.5 <= args.interval <= 10:
        parser.error('--interval must be between 0.5 and 10 seconds')
    telemetry = Telemetry()
    stopped = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stopped.set())
    try:
        if not args.stream:
            telemetry.sample()
            stopped.wait(.12)
            if not stopped.is_set():
                print(json.dumps(telemetry.sample(), allow_nan=False), flush=True)
            return
        while not stopped.is_set():
            started = time.monotonic()
            print(json.dumps(telemetry.sample(), allow_nan=False), flush=True)
            stopped.wait(max(0, args.interval - (time.monotonic() - started)))
    except BrokenPipeError:
        sys.stdout = open('/dev/null', 'w')


if __name__ == '__main__':
    main()
