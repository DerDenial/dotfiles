#!/usr/bin/env python3
"""Bounded, explicit HTTP speed test against Cloudflare; JSON snapshots on stdout.

No daemon, credentials, result upload or test runs merely by importing this file.
"""
from __future__ import annotations

from dataclasses import dataclass
import http.client
import json
import math
import signal
import socket
import ssl
import statistics
import sys
import threading
import time
from urllib.parse import urlencode

HOST = 'speed.cloudflare.com'
PROVIDER = 'Cloudflare'
BLOCK = 64 * 1024
DEFAULT_DOWNLOAD_BUDGET = 150_000_000
DEFAULT_UPLOAD_BUDGET = 100_000_000


class Cancelled(Exception):
    pass


class TestError(Exception):
    pass


@dataclass(frozen=True)
class Settings:
    workers: int = 3
    latency_samples: int = 6
    latency_seconds: float = 8.0
    phase_seconds: float = 6.0
    total_seconds: float = 24.0
    download_budget: int = DEFAULT_DOWNLOAD_BUDGET
    upload_budget: int = DEFAULT_UPLOAD_BUDGET
    update_seconds: float = 0.2
    io_timeout: float = 1.5


class Token:
    """A phase token with independently closable owned HTTPS connections."""
    def __init__(self, cancelled, deadline, clock=time.monotonic):
        self.cancelled = cancelled
        self.deadline = deadline
        self.clock = clock
        self.stopped = threading.Event()
        self.lock = threading.RLock()
        self.connections = set()

    def check(self):
        if self.cancelled.is_set() or self.stopped.is_set() or self.clock() >= self.deadline:
            raise Cancelled()

    def add(self, connection):
        self.check()
        with self.lock:
            self.connections.add(connection)
        try:
            self.check()
        except Cancelled:
            self.remove(connection)
            connection.close()
            raise

    def remove(self, connection):
        with self.lock:
            self.connections.discard(connection)

    def stop(self):
        self.stopped.set()
        with self.lock:
            owned = list(self.connections)
        for connection in owned:
            # Shutdown unblocks a concurrent SSL recv/send before HTTPResponse.close
            # can wait on the response file's own read lock.
            stream = getattr(connection, 'sock', None)
            if stream is not None:
                try:
                    stream.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            try:
                connection.close()
            except (OSError, ValueError):
                pass


class CloudflareHTTP:
    def __init__(self, token, io_timeout=1.5, connection_factory=None):
        self.token = token
        self.io_timeout = io_timeout
        self.factory = connection_factory or http.client.HTTPSConnection
        self.connection = None

    def connect(self):
        self.token.check()
        if self.connection is None:
            timeout = max(0.05, min(self.io_timeout, self.token.deadline - self.token.clock()))
            self.connection = self.factory(HOST, timeout=timeout, context=ssl.create_default_context())
            self.token.add(self.connection)
            self.connection.connect()
            self.token.check()
        return self.connection

    def close(self):
        if self.connection is not None:
            connection = self.connection
            self.connection = None
            self.token.remove(connection)
            try:
                connection.close()
            except (OSError, ValueError):
                pass

    def request(self, method, size):
        connection = self.connect()
        self.token.check()
        path = ('/__down' if method == 'GET' else '/__up') + '?' + urlencode({
            'bytes': size, 'qs': time.monotonic_ns()
        })
        connection.putrequest(method, path)
        connection.putheader('User-Agent', 'Quickshell-SpeedTest/1.0')
        connection.putheader('Accept-Encoding', 'identity')
        connection.putheader('Cache-Control', 'no-cache')
        if method == 'POST':
            connection.putheader('Content-Type', 'application/octet-stream')
            connection.putheader('Content-Length', str(size))
        connection.endheaders()
        return connection

    @staticmethod
    def valid_response(response):
        if response.status != 200:
            if response.status == 429:
                raise TestError('Cloudflare is busy. Wait a moment and try again.')
            raise TestError(f'Cloudflare returned HTTP {response.status}. Try again later.')
        encoding = (response.getheader('Content-Encoding') or 'identity').strip().lower()
        if encoding not in ('', 'identity'):
            raise TestError('The test response was compressed; a reliable measurement is unavailable.')

    def latency(self):
        self.connect()  # Exclude the initial DNS/TCP/TLS setup from HTTP latency.
        started = self.token.clock()
        connection = self.request('GET', 0)
        response = connection.getresponse()
        received = self.token.clock()
        self.valid_response(response)
        # Zero-body endpoint; a bounded read avoids consuming an unexpected body.
        if response.read(1):
            raise TestError('Cloudflare returned an unexpected latency response.')
        response.close()
        self.token.check()
        return max(0.0, (received - started) * 1000)

    def transfer(self, direction, size, account):
        self.token.check()
        connection = self.request('GET' if direction == 'download' else 'POST', size)
        if direction == 'upload':
            remaining = size
            payload = bytes(BLOCK)
            while remaining:
                self.token.check()
                length = min(BLOCK, remaining)
                connection.send(payload[:length])
                account(length)
                remaining -= length
        response = connection.getresponse()
        self.valid_response(response)
        if direction == 'download':
            expected_length = response.getheader('Content-Length')
            if expected_length is not None and expected_length != str(size):
                raise TestError('Cloudflare returned an unexpected download size.')
            received = 0
            while received < size:
                self.token.check()
                block = response.read(min(BLOCK, size - received))
                if not block:
                    raise TestError('The download ended before the requested test data arrived.')
                received += len(block)
                account(len(block))
        else:
            # An upload counts as confirmed only after the success response.
            # The endpoint's small response is drained up to a strict bound.
            if len(response.read(4097)) > 4096:
                raise TestError('Cloudflare returned an unexpected upload response.')
        response.close()
        self.token.check()
        return size


class PhaseStats:
    def __init__(self, budget):
        self.lock = threading.Lock()
        self.budget = budget
        self.reserved = 0
        self.transferred = 0
        self.confirmed = 0
        self.errors = []

    def reserve(self, requested):
        with self.lock:
            amount = min(max(0, requested), self.budget - self.reserved)
            self.reserved += amount
            return amount

    def account(self, amount):
        with self.lock:
            self.transferred += amount

    def confirm(self, amount):
        with self.lock:
            self.confirmed += amount

    def fail(self, error):
        with self.lock:
            self.errors.append(error)

    def values(self):
        with self.lock:
            return self.transferred, self.confirmed, list(self.errors)


def mbps(byte_count, seconds):
    return byte_count * 8 / seconds / 1_000_000 if seconds > 0 else 0.0


def latency_summary(samples):
    if not samples:
        return None, None
    median = statistics.median(samples)
    jitter = statistics.mean(abs(right - left) for left, right in zip(samples, samples[1:])) if len(samples) > 1 else None
    return median, jitter


class Runner:
    def __init__(self, output=None, *, settings=None, cancelled=None, transport_factory=None, clock=time.monotonic):
        self.output = output or (lambda value: print(json.dumps(value, allow_nan=False), flush=True))
        self.settings = settings or Settings()
        self.cancelled = cancelled or threading.Event()
        self.transport_factory = transport_factory or (lambda token: CloudflareHTTP(token, self.settings.io_timeout))
        self.clock = clock
        self.started = clock()
        self.deadline = self.started + self.settings.total_seconds
        self.active_token = None
        self.last_emit = -math.inf
        self.snapshot = {
            'phase': 'latency', 'progress': 0.0, 'downloadMbps': None,
            'uploadMbps': None, 'latencyMs': None, 'jitterMs': None,
            'liveMbps': None, 'bytesTransferred': 0, 'provider': PROVIDER,
            'error': '', 'elapsed': 0.0,
        }

    def emit(self, *, force=False, **changes):
        self.snapshot.update(changes)
        now = self.clock()
        if force or now - self.last_emit >= self.settings.update_seconds:
            self.last_emit = now
            value = dict(self.snapshot)
            value['elapsed'] = round(max(0.0, now - self.started), 2)
            for key in ('progress', 'downloadMbps', 'uploadMbps', 'latencyMs', 'jitterMs', 'liveMbps'):
                if isinstance(value[key], float):
                    value[key] = round(value[key], 3)
            self.output(value)

    def cancel(self):
        self.cancelled.set()
        token = self.active_token
        if token is not None:
            token.stop()

    def check(self):
        if self.cancelled.is_set():
            raise Cancelled()
        if self.clock() >= self.deadline:
            raise TestError('The test timed out. Check your connection and try again.')

    def measure_latency(self):
        token = Token(self.cancelled, min(self.deadline, self.clock() + self.settings.latency_seconds), self.clock)
        self.active_token = token
        result = []
        errors = []
        finished = threading.Event()

        def worker():
            transport = self.transport_factory(token)
            try:
                # Warm the existing HTTPS connection; no artificial zero result.
                transport.latency()
                for _ in range(self.settings.latency_samples):
                    token.check()
                    result.append(transport.latency())
            except Cancelled:
                pass
            except (OSError, ValueError, http.client.HTTPException, TestError) as error:
                errors.append(error)
            finally:
                try:
                    transport.close()
                except (OSError, ValueError):
                    pass
                finally:
                    finished.set()

        thread = threading.Thread(target=worker, daemon=True, name='speedtest-latency')
        thread.start()
        self.emit(force=True, phase='latency', progress=0.0)
        while not finished.wait(self.settings.update_seconds):
            self.check()
            if self.clock() >= token.deadline:
                break
            ping, jitter = latency_summary(result)
            self.emit(latencyMs=ping, jitterMs=jitter, progress=0.15 * len(result) / self.settings.latency_samples)
        token.stop()
        thread.join(timeout=0.1)
        self.active_token = None
        self.check()
        if errors:
            raise errors[0]
        if len(result) < 2:
            raise TestError('The latency test timed out. Check your connection and try again.')
        ping, jitter = latency_summary(result)
        self.emit(force=True, latencyMs=ping, jitterMs=jitter, progress=0.15)

    def measure_bandwidth(self, direction, budget, progress_start, progress_span):
        self.check()
        phase_start = self.clock()
        token = Token(self.cancelled, min(self.deadline, phase_start + self.settings.phase_seconds), self.clock)
        self.active_token = token
        stats = PhaseStats(budget)
        previous_bytes = 0
        previous_time = phase_start
        total_before = self.snapshot['bytesTransferred']
        finished = [threading.Event() for _ in range(self.settings.workers)]

        def worker(done):
            transport = self.transport_factory(token)
            next_size = 10_000_000 if direction == 'download' else BLOCK
            try:
                while True:
                    token.check()
                    size = stats.reserve(next_size)
                    if not size:
                        break
                    requested = self.clock()
                    completed = transport.transfer(direction, size, stats.account)
                    stats.confirm(completed)
                    if direction == 'upload':
                        elapsed = self.clock() - requested
                        # Keep uploads short enough that slow links can confirm
                        # a sample and a bounded tail is lost on cancellation.
                        if elapsed > 0:
                            next_size = min(2_000_000, max(BLOCK, int(completed / elapsed * 0.4)))
            except Cancelled:
                pass
            except (OSError, ValueError, http.client.HTTPException, TestError) as error:
                if not self.cancelled.is_set() and self.clock() < token.deadline and not token.stopped.is_set():
                    stats.fail(error)
                    token.stop()
            finally:
                try:
                    transport.close()
                except (OSError, ValueError):
                    pass
                finally:
                    done.set()

        threads = [threading.Thread(target=worker, args=(done,), daemon=True, name='speedtest-' + direction) for done in finished]
        self.emit(force=True, phase=direction, progress=progress_start, liveMbps=0.0)
        for thread in threads:
            thread.start()
        while True:
            self.check()
            now = self.clock()
            sent, confirmed, errors = stats.values()
            current = mbps(sent - previous_bytes, now - previous_time)
            previous_bytes, previous_time = sent, now
            elapsed = max(0.0, now - phase_start)
            progress = max(elapsed / self.settings.phase_seconds, sent / budget if budget else 1)
            self.emit(liveMbps=current, bytesTransferred=total_before + sent,
                      progress=progress_start + progress_span * min(1.0, progress))
            if errors or all(done.is_set() for done in finished) or now >= token.deadline:
                break
            self.cancelled.wait(min(self.settings.update_seconds, max(0.0, token.deadline - now)))
        token.stop()
        for thread in threads:
            thread.join(timeout=0.05)
        self.active_token = None
        self.check()
        elapsed = max(0.001, self.clock() - phase_start)
        sent, confirmed, errors = stats.values()
        self.snapshot['bytesTransferred'] = total_before + sent
        if errors:
            raise errors[0]
        useful = sent if direction == 'download' else confirmed
        if useful <= 0:
            raise TestError(f'No {direction} data could be measured. Check your connection and try again.')
        value = mbps(useful, elapsed)
        self.emit(force=True, **{direction + 'Mbps': value},
                  liveMbps=value, bytesTransferred=total_before + sent,
                  progress=progress_start + progress_span)

    def run(self):
        try:
            self.measure_latency()
            self.measure_bandwidth('download', self.settings.download_budget, 0.15, 0.425)
            self.measure_bandwidth('upload', self.settings.upload_budget, 0.575, 0.425)
            self.emit(force=True, phase='complete', progress=1.0, liveMbps=None)
            return 0
        except Cancelled:
            self.emit(force=True, phase='cancelled', liveMbps=None, error='')
            return 0
        except (OSError, ValueError, http.client.HTTPException, TestError) as error:
            message = str(error) if isinstance(error, TestError) else 'The connection failed. Check your network and try again.'
            self.emit(force=True, phase='error', liveMbps=None, error=message)
            return 1
        finally:
            if self.active_token is not None:
                self.active_token.stop()
                self.active_token = None


def main():
    if sys.argv[1:]:
        raise SystemExit('Usage: run.py')
    runner = Runner()
    # Signal handlers only set a flag. Main-loop cleanup closes owned sockets
    # outside the handler, avoiding reentrant IO or lock acquisition.
    signal.signal(signal.SIGTERM, lambda *_: runner.cancelled.set())
    signal.signal(signal.SIGINT, lambda *_: runner.cancelled.set())
    try:
        return runner.run()
    except BrokenPipeError:
        runner.cancel()
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
