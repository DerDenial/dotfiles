#!/usr/bin/env python3
"""Small, read-only snapshots for the desktop settings UI; no shell commands."""
import glob
import json
import os
from pathlib import Path
import platform
import re
import shutil
import socket
import subprocess
import sys


def read(path, fallback=""):
    try:
        return Path(path).read_text().strip()
    except (OSError, UnicodeError):
        return fallback


def number(path, fallback=0):
    try:
        return float(read(path))
    except ValueError:
        return fallback


def run(args, timeout=2):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as error:
        return -1, "", str(error)


def unescape_mount(value):
    return re.sub(r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), value)


def storage(path):
    try:
        stat = os.statvfs(path)
        total = stat.f_blocks * stat.f_frsize
        free = stat.f_bavail * stat.f_frsize
        used = (stat.f_blocks - stat.f_bfree) * stat.f_frsize
        candidates = []
        for line in read("/proc/self/mountinfo").splitlines():
            left, right = line.split(" - ", 1)
            mount = unescape_mount(left.split()[4])
            if path == mount or path.startswith(mount.rstrip("/") + "/"):
                fields = right.split()
                candidates.append((len(mount), unescape_mount(fields[1]), fields[0], mount))
        _, source, filesystem, mount = max(candidates) if candidates else (0, "", "", path)
        return {"path": path, "total": total, "free": free, "used": used,
                "percent": round(used / total * 100, 1) if total else 0,
                "source": source, "filesystem": filesystem, "mount": mount}
    except (OSError, ValueError, IndexError):
        return {"path": path, "error": "Storage information unavailable"}


def temperatures_snapshot():
    """One useful reading per component, rather than raw driver channels."""
    components = {"cpu": {}, "gpu": {}, "ssd": {}}
    platform_fallbacks = {"cpu": [], "gpu": []}

    def add(kind, device, samples):
        if not samples:
            return
        # Prefer a component-wide sensor. For equal-ranked core readings,
        # use the warmest core instead of whichever file happens to sort first.
        rank, value = min(samples, key=lambda item: (item[0], -item[1]))
        previous = components[kind].get(device)
        if previous is None or (rank, -value) < (previous[0], -previous[1]):
            components[kind][device] = (rank, value)

    for folder in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
        chip = read(folder / "name").casefold()
        device = str((folder / "device").resolve())
        samples = []
        for sensor in sorted(folder.glob("temp*_input")):
            prefix = sensor.name.removesuffix("_input")
            if read(folder / (prefix + "_fault")) == "1" or read(folder / (prefix + "_enable")) == "0":
                continue
            value = number(sensor, -999000) / 1000
            if not -30 <= value <= 150:
                continue
            label = read(folder / (prefix + "_label")).casefold()
            samples.append((prefix, label, value))

        if chip == "k10temp":
            add("cpu", device, [(0 if label == "tdie" else 1, value)
                                for prefix, label, value in samples
                                if label in ("tdie", "tctl") or (prefix == "temp1" and not label)])
        elif chip == "coretemp":
            add("cpu", device, [(0 if label.startswith("package") else 1, value)
                                for prefix, label, value in samples
                                if label.startswith(("package", "core ")) or (prefix == "temp1" and not label)])
        elif chip in ("amdgpu", "radeon", "nouveau", "nvidia", "i915", "xe"):
            add("gpu", device, [(0 if label == "edge" else 1 if prefix == "temp1" else 2, value)
                                for prefix, label, value in samples
                                if label == "edge" or (prefix == "temp1" and label not in ("mem", "memory"))
                                or label in ("junction", "hotspot")])
        elif chip == "nvme":
            add("ssd", device, [(0 if label == "composite" else 1, value)
                                for prefix, label, value in samples
                                if label == "composite" or prefix == "temp1"])
        elif chip == "thinkpad":
            # Firmware channel positions vary between ThinkPad models. Only
            # explicitly labelled CPU/GPU channels are safe fallbacks; unused
            # slots reporting 0 °C must not appear as real components.
            for _, label, value in samples:
                if value > 0 and label in ("cpu", "gpu"):
                    platform_fallbacks[label].append(value)

    details = {"cpu": ("CPU", "Prozessor", "memory"),
               "gpu": ("GPU", "Grafikchip", "developer_board"),
               "ssd": ("SSD", "SSD-Laufwerk", "storage")}
    result = []
    for kind, (title, description, icon) in details.items():
        readings = [reading[1] for _, reading in sorted(components[kind].items())]
        if not readings and platform_fallbacks.get(kind):
            readings = [max(platform_fallbacks[kind])]
        for index, value in enumerate(readings, 1):
            suffix = " " + str(index) if len(readings) > 1 else ""
            result.append({"id": kind + str(index), "name": title + suffix,
                           "description": description, "icon": icon,
                           "value": round(value, 1)})
    return result


def system_snapshot():
    mem = {}
    for line in read("/proc/meminfo").splitlines():
        fields = line.split()
        if len(fields) >= 2:
            mem[fields[0].rstrip(":")] = int(fields[1]) * 1024
    cpu_fields = read("/proc/stat").splitlines()[0].split()[1:9]
    ticks = [int(value) for value in cpu_fields]
    os_info = {}
    for line in read("/etc/os-release").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            os_info[key] = value.strip('"')
    cpu_name = next((line.split(":", 1)[1].strip() for line in read("/proc/cpuinfo").splitlines()
                     if line.startswith("model name") and ":" in line), platform.machine())
    total = mem.get("MemTotal", 0)
    used = max(0, total - mem.get("MemAvailable", mem.get("MemFree", 0)))
    return {"hostname": socket.gethostname(), "os": os_info.get("PRETTY_NAME", "Linux"),
            "kernel": platform.release(), "architecture": platform.machine(), "cpuName": cpu_name,
            "cpuThreads": os.cpu_count() or 0, "cpuTotal": sum(ticks), "cpuIdle": ticks[3] + ticks[4],
            "memoryTotal": total, "memoryUsed": used, "memoryPercent": round(used / total * 100, 1) if total else 0,
            "swapTotal": mem.get("SwapTotal", 0), "swapUsed": mem.get("SwapTotal", 0) - mem.get("SwapFree", 0),
            "uptime": int(float(read("/proc/uptime", "0").split()[0])),
            "storage": [storage(os.path.expanduser("~")), storage("/")],
            "temperatures": temperatures_snapshot(),
            "systemMonitor": bool(shutil.which("gnome-system-monitor")),
            "clipboard": bool(shutil.which("wl-copy"))}


def display_snapshot():
    brightness = {"available": False, "percent": 0, "device": ""}
    code, output, error = run(["brightnessctl", "-c", "backlight", "-m"])
    if code == 0 and output:
        fields = output.splitlines()[0].split(",")
        if len(fields) >= 5:
            try:
                brightness = {"available": True, "device": fields[0], "percent": float(fields[3].rstrip("%"))}
            except ValueError:
                pass
    elif error:
        brightness["error"] = error.splitlines()[0]
    code, output, error = run(["hyprctl", "monitors", "-j"])
    monitors = []
    if code == 0:
        try:
            for monitor in json.loads(output):
                monitors.append({key: monitor.get(key) for key in
                                 ("name", "description", "width", "height", "refreshRate", "scale", "x", "y", "focused", "disabled", "transform")})
        except (ValueError, TypeError):
            pass
    return {"brightness": brightness, "monitors": monitors,
            "monitorError": "" if monitors else "Monitor information is currently unavailable."}


def power_snapshot():
    batteries = []
    for folder in sorted(glob.glob("/sys/class/power_supply/*")):
        path = Path(folder)
        if read(path / "type") != "Battery" or read(path / "present", "1") == "0":
            continue
        full = number(path / "energy_full") or number(path / "charge_full")
        design = number(path / "energy_full_design") or number(path / "charge_full_design")
        batteries.append({"name": path.name, "model": read(path / "model_name"),
                          "status": read(path / "status", "Unknown"),
                          "percent": number(path / "capacity"),
                          "health": round(full / design * 100, 1) if design else None,
                          "cycles": number(path / "cycle_count", -1),
                          "rate": number(path / "power_now", -1) / 1000000,
                          "energy": number(path / "energy_now", -1) / 1000000,
                          "capacity": number(path / "energy_full", -1) / 1000000})
    available = bool(shutil.which("tlp"))
    profile = ""
    if available:
        _, output, _ = run(["tlp-stat", "-s"])
        match = re.search(r"^TLP profile\s*=\s*([^/\s]+)", output, re.MULTILINE)
        if match:
            profile = match[1]
    if not profile:
        platform_profile = read("/sys/firmware/acpi/platform_profile")
        profile = {"low-power": "power-saver", "balanced": "balanced", "performance": "performance"}.get(platform_profile, "")
    _, state, _ = run(["systemctl", "is-enabled", "tlp.service"])
    capabilities = {}
    for action in ("Suspend", "Hibernate"):
        _, result, _ = run(["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                            "org.freedesktop.login1.Manager", "Can" + action])
        capabilities[action.lower()] = result.split('"')[1] if '"' in result else "unknown"
    return {"batteries": batteries, "profile": profile, "tlpAvailable": available,
            "tlpServiceState": state, "platformProfile": read("/sys/firmware/acpi/platform_profile"),
            "epp": read("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
            "capabilities": capabilities,
            "lockAvailable": bool(shutil.which("hyprlock"))}


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "system"
    try:
        snapshot = {"system": system_snapshot, "display": display_snapshot, "power": power_snapshot}[mode]()
    except Exception as error:
        snapshot = {"error": str(error)}
    print(json.dumps(snapshot, ensure_ascii=False))
