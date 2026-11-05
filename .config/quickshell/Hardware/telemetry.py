#!/usr/bin/env python3
"""Read-only, on-demand Linux hardware telemetry for the Quickshell panel.

No selected processes, network services or device settings are accessed. A single
helper streams while its panel is open; closing its pipe or sending SIGTERM
stops it. Linux power_supply micro-units are converted to Wh/W at this boundary.
"""
from __future__ import annotations

import argparse
from collections import deque
import json
import math
from pathlib import Path
import platform
import re
import signal
import sys
import threading
import time


def read(path, default=''):
    try:
        with Path(path).open(encoding='utf-8', errors='replace') as stream:
            return stream.read(65536).strip()
    except OSError:
        return default


def number(path):
    try:
        result = float(read(path))
        return result if math.isfinite(result) else None
    except ValueError:
        return None


def nonnegative(value):
    return value if value is not None and value >= 0 else None


def positive(value):
    return value if value is not None and value > 0 else None


def rounded(value, digits=2):
    return round(value, digits) if value is not None else None


class Telemetry:
    def __init__(self, proc='/proc', sysroot='/sys', pci_paths=None, clock=None, wallclock=None):
        self.proc = Path(proc)
        self.sys = Path(sysroot)
        self.clock = clock or time.monotonic
        self.wallclock = wallclock or time.time
        self.cpu_previous = None
        self.cpu_name = self.read_cpu_name()
        self.pci_paths = tuple(Path(path) for path in (pci_paths if pci_paths is not None else
                               ('/usr/share/hwdata/pci.ids', '/usr/share/misc/pci.ids')))
        self.pci_names = self.read_pci_names()
        self.gpu_devices = self.discover_gpus()
        self.gpu_discovery_at = self.clock()
        self.power_samples = deque(maxlen=20)
        self.power_mode = None

    def read_cpu_name(self):
        for line in read(self.proc / 'cpuinfo').splitlines():
            if ':' in line and line.split(':', 1)[0].strip() in ('model name', 'Hardware'):
                value = line.split(':', 1)[1].strip()
                if value:
                    return value
        return platform.machine() + ' processor'

    def read_pci_names(self):
        # Parse once per helper lifetime, never spawn lspci on a sampling timer.
        for path in self.pci_paths:
            try:
                result = {}
                vendor = None
                with path.open(encoding='utf-8', errors='replace') as stream:
                    for line in stream:
                        match = re.match(r'^([0-9a-fA-F]{4})\s+(.+)', line)
                        if match:
                            vendor = match[1].lower()
                            result[(vendor, '')] = match[2].strip()
                        elif vendor:
                            match = re.match(r'^\t([0-9a-fA-F]{4})\s+(.+)', line)
                            if match:
                                result[(vendor, match[1].lower())] = match[2].strip()
                return result
            except OSError:
                continue
        return {}

    def gpu_name(self, device):
        vendor = read(device / 'vendor').lower().removeprefix('0x')
        ident = read(device / 'device').lower().removeprefix('0x')
        brand = {'1002': 'AMD', '10de': 'NVIDIA', '8086': 'Intel'}.get(vendor, '')
        model = self.pci_names.get((vendor, ident), '')
        if brand == 'AMD' and 'Radeon Vega' in model and '[' in model:
            codename = model.split('[', 1)[0].strip()
            return 'AMD Radeon Vega' + (' (' + codename + ')' if codename else '')
        if model:
            return (brand + ' ' + model).strip()
        return ((brand + ' GPU') if brand else 'Graphics processor') + (
            ' (' + vendor + ':' + ident + ')' if vendor and ident else '')

    def discover_gpus(self):
        result = []
        seen = set()
        for card in sorted((self.sys / 'class/drm').glob('card[0-9]*')):
            if not re.fullmatch(r'card\d+', card.name):
                continue
            device = (card / 'device').resolve()
            if not device.is_dir() or device in seen:
                continue
            # Real PCI GPUs expose vendor/device. Connector aliases are excluded.
            if not (device / 'vendor').is_file() or not (device / 'device').is_file():
                continue
            device_class = read(device / 'class')
            if device_class:
                try:
                    if int(device_class, 16) >> 16 != 0x03:
                        continue
                except ValueError:
                    continue
            seen.add(device)
            result.append({'id': device.name, 'path': device, 'name': self.gpu_name(device)})
        return result

    def cpu_usage(self):
        try:
            line = read(self.proc / 'stat').splitlines()[0].split()
            if not line or line[0] != 'cpu' or len(line) < 5:
                raise ValueError
            fields = [int(value) for value in line[1:9]]
            if any(value < 0 for value in fields):
                raise ValueError
            current = (sum(fields), fields[3] + (fields[4] if len(fields) > 4 else 0))
        except (ValueError, IndexError):
            self.cpu_previous = None
            return None
        previous, self.cpu_previous = self.cpu_previous, current
        if previous is None:
            return None
        total, idle = current[0] - previous[0], current[1] - previous[1]
        if total <= 0 or idle < 0 or idle > total:
            return None
        return round(100 * (total - idle) / total, 1)

    def sensor_readings(self, folder):
        result = []
        for path in sorted(folder.glob('temp*_input')):
            prefix = path.name.removesuffix('_input')
            if read(folder / (prefix + '_fault')) == '1' or read(folder / (prefix + '_enable')) == '0':
                continue
            value = number(path)
            if value is None or not -30000 <= value <= 150000:
                continue
            result.append((prefix, read(folder / (prefix + '_label')).casefold(), value / 1000))
        return result

    def temperatures(self):
        cpu = []
        fallbacks = []
        gpu = {}
        for folder in sorted((self.sys / 'class/hwmon').glob('hwmon*')):
            chip = read(folder / 'name').casefold()
            samples = self.sensor_readings(folder)
            if chip == 'k10temp':
                cpu.extend((0 if label == 'tdie' else 1, value) for prefix, label, value in samples
                           if label in ('tdie', 'tctl') or prefix == 'temp1' and not label)
            elif chip == 'coretemp':
                cpu.extend((0 if label.startswith('package') else 1, value) for prefix, label, value in samples
                           if label.startswith(('package', 'core ')) or prefix == 'temp1' and not label)
            elif chip == 'thinkpad':
                fallbacks.extend(value for _, label, value in samples if label == 'cpu' and value > 0)
            elif chip in ('amdgpu', 'radeon', 'nouveau', 'nvidia', 'i915', 'xe'):
                readings = [(0 if label == 'edge' else 1 if prefix == 'temp1' else 2, value)
                            for prefix, label, value in samples
                            if label == 'edge' or prefix == 'temp1' and label not in ('mem', 'memory')
                            or label in ('junction', 'hotspot')]
                if readings:
                    device = (folder / 'device').resolve()
                    gpu[device] = min(readings, key=lambda item: (item[0], -item[1]))[1]
        cpu_temp = min(cpu, key=lambda item: (item[0], -item[1]))[1] if cpu else max(fallbacks) if fallbacks else None
        return cpu_temp, gpu

    def battery_device(self, folder):
        status = read(folder / 'status', 'Unknown')
        energy = nonnegative(number(folder / 'energy_now'))
        full = positive(number(folder / 'energy_full'))
        approximate = False
        nominal_voltage = positive(number(folder / 'voltage_min_design'))
        voltage = positive(number(folder / 'voltage_now'))
        # Charge-only drivers expose micro-Ah. Convert both capacities using the
        # same nominal voltage so "full" does not fluctuate with cell voltage.
        conversion_voltage = nominal_voltage or voltage
        if energy is None:
            charge = nonnegative(number(folder / 'charge_now'))
            if charge is not None and conversion_voltage is not None:
                energy = charge * conversion_voltage / 1_000_000
                approximate = True
        if full is None:
            charge = positive(number(folder / 'charge_full'))
            if charge is not None and conversion_voltage is not None:
                full = charge * conversion_voltage / 1_000_000
                approximate = True
        power = nonnegative(number(folder / 'power_now'))
        if power is None:
            current = number(folder / 'current_now')
            if current is not None and voltage is not None:
                power = abs(current) * voltage / 1_000_000
        capacity = number(folder / 'capacity')
        if capacity is None and energy is not None and full is not None:
            capacity = energy / full * 100
        return {'name': folder.name, 'status': status, 'energy': energy / 1_000_000 if energy is not None else None,
                'full': full / 1_000_000 if full is not None else None,
                'power': power / 1_000_000 if power is not None else None,
                'percent': max(0, min(100, capacity)) if capacity is not None else None,
                'approximate': approximate}

    def battery(self, now):
        supplies = self.sys / 'class/power_supply'
        batteries = []
        external = False
        for folder in sorted(supplies.glob('*')):
            if read(folder / 'type') == 'Battery':
                if read(folder / 'present', '1') != '0' and read(folder / 'scope') != 'Device':
                    batteries.append(self.battery_device(folder))
            elif read(folder / 'scope') != 'Device' and read(folder / 'online') == '1':
                external = True
        result = {'present': bool(batteries), 'name': '', 'status': 'Unavailable', 'percent': None,
                  'fullWh': None, 'storedWh': None, 'powerW': None, 'draining': False, 'charging': False,
                  'remainingSeconds': None, 'chargingSeconds': None, 'estimated': False,
                  'energyApproximate': False, 'externalPower': external}
        if not batteries:
            self.power_samples.clear()
            self.power_mode = None
            return result
        result['name'] = batteries[0]['name'] if len(batteries) == 1 else str(len(batteries)) + ' batteries'
        result['energyApproximate'] = any(battery['approximate'] for battery in batteries)
        if all(battery['energy'] is not None for battery in batteries):
            result['storedWh'] = sum(battery['energy'] for battery in batteries)
        if all(battery['full'] is not None for battery in batteries):
            result['fullWh'] = sum(battery['full'] for battery in batteries)
        if len(batteries) == 1:
            result['percent'] = batteries[0]['percent']
            result['status'] = batteries[0]['status']
            result['powerW'] = batteries[0]['power']
        else:
            full = result['fullWh']
            energy = result['storedWh']
            if full is not None and energy is not None and full > 0:
                result['percent'] = max(0, min(100, energy / full * 100))
            statuses = set(battery['status'] for battery in batteries)
            result['status'] = next(iter(statuses)) if len(statuses) == 1 else 'Mixed'
            if all(battery['power'] is not None for battery in batteries):
                signs = {'Discharging': -1, 'Charging': 1, 'Full': 0, 'Not charging': 0}
                if all(battery['status'] in signs for battery in batteries):
                    signed = sum(battery['power'] * signs[battery['status']] for battery in batteries)
                    result['powerW'] = abs(signed)
                    result['status'] = 'Charging' if signed > 0.01 else 'Discharging' if signed < -0.01 else 'Not charging'
        result['draining'] = result['status'] == 'Discharging'
        result['charging'] = result['status'] == 'Charging'
        mode = (result['name'], result['status'])
        if mode != self.power_mode:
            self.power_samples.clear()
            self.power_mode = mode
        if result['powerW'] is not None and (result['draining'] or result['charging']):
            self.power_samples.append((now, result['powerW']))
        while self.power_samples and now - self.power_samples[0][0] > 30:
            self.power_samples.popleft()
        average = sum(value for _, value in self.power_samples) / len(self.power_samples) if self.power_samples else None
        # Battery flow near zero cannot produce a credible remaining-time claim.
        if result['powerW'] is not None and result['powerW'] > 0.1 and average is not None and average > 0.1:
            if result['draining'] and result['storedWh'] is not None:
                result['remainingSeconds'] = round(result['storedWh'] / average * 3600)
                result['estimated'] = True
            elif result['charging'] and result['storedWh'] is not None and result['fullWh'] is not None:
                result['chargingSeconds'] = round(max(0, result['fullWh'] - result['storedWh']) / average * 3600)
                result['estimated'] = True
        for key in ('percent', 'fullWh', 'storedWh', 'powerW'):
            result[key] = rounded(result[key], 1 if key == 'percent' else 2)
        return result

    def sample(self):
        now = self.clock()
        if now - self.gpu_discovery_at > 30:
            self.gpu_devices = self.discover_gpus()
            self.gpu_discovery_at = now
        warnings = []
        cpu_temp, gpu_temps = self.temperatures()
        gpus = []
        for gpu in self.gpu_devices:
            usage = number(gpu['path'] / 'gpu_busy_percent')
            if usage is not None and not 0 <= usage <= 100:
                usage = None
            gpus.append({'id': gpu['id'], 'name': gpu['name'], 'usagePercent': rounded(usage, 1),
                         'temperatureC': rounded(gpu_temps.get(gpu['path']), 1)})
        return {'ok': True, 'timestamp': self.wallclock(), 'monotonic': now,
                'cpu': {'name': self.cpu_name, 'usagePercent': self.cpu_usage(),
                        'temperatureC': rounded(cpu_temp, 1)},
                'gpus': gpus, 'battery': self.battery(now), 'warnings': warnings}


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
            stopped.wait(0.12)
            if not stopped.is_set():
                print(json.dumps(telemetry.sample(), allow_nan=False), flush=True)
            return
        while not stopped.is_set():
            started = time.monotonic()
            print(json.dumps(telemetry.sample(), allow_nan=False), flush=True)
            stopped.wait(max(0, args.interval - (time.monotonic() - started)))
    except BrokenPipeError:
        # The owning panel was closed. Do not retain a polling process.
        sys.stdout = open('/dev/null', 'w')


if __name__ == '__main__':
    main()
