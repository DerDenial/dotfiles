#!/usr/bin/env python3
"""Live process accounting for Quickshell's Task Manager, using only /proc.

No arguments, environment variables, process contents, or history are collected.
CPU is the interval's share of all logical CPUs (100% means the whole machine).
Memory is resident memory (RSS); shared pages may occur in several processes.
Network rates sum non-loopback interfaces. Storage rates count whole physical
block devices only, excluding partitions and stacked device-mapper/md devices.
Unreadable counters and the initial CPU/I/O measurement are reported as null.

--watch keeps one collector alive while its stdin pipe remains open. --end is a
separate, explicit action: it sends SIGTERM to one validated, same-user process
through a pidfd, never a PID after a potentially racy identity check.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import pwd
import select
import signal
import sys
import time
from typing import Any


INTERVAL = 1.5
MAX_PROCESSES = 32768
MAX_TEXT = 65536
PROTECTED_NAMES = frozenset({
    "qs", "quickshell", "hyprland", "hyprlock", "hypridle", "systemd",
    "systemd-logind", "systemd-userwor", "dbus-daemon", "dbus-broker",
    "dbus-broker-launch", "sddm", "sddm-helper", "xwayland", "xorg",
    "gnome-shell", "plasmashell", "kwin_wayland", "sway", "wayfire",
})
STATE_NAMES = {
    "R": "Running", "S": "Sleeping", "D": "Waiting", "Z": "Zombie",
    "T": "Stopped", "t": "Traced", "I": "Idle", "X": "Exited", "x": "Exited",
    "K": "Waiting", "W": "Waiting", "P": "Parked",
}


def clean(value: str, limit: int = 96) -> str:
    return " ".join("".join(c for c in str(value) if c.isprintable()).split())[:limit]


def read_text(path: Path, limit: int = MAX_TEXT) -> str:
    with path.open("rb") as source:
        data = source.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Counter file is too large")
    return data.decode("utf-8", errors="replace")


def nonnegative(value: str | int | float) -> int:
    number = int(value)
    if number < 0:
        raise ValueError("Negative counter")
    return number


def parse_stat(text: str, expected_pid: int | None = None) -> dict[str, Any]:
    """Parse stat without splitting its parenthesized, potentially spaced name."""
    opening, closing = text.find("("), text.rfind(")")
    if opening <= 0 or closing <= opening:
        raise ValueError("Invalid process stat")
    pid = nonnegative(text[:opening].strip())
    if expected_pid is not None and pid != expected_pid:
        raise ValueError("Process identity changed")
    fields = text[closing + 1:].split()
    if len(fields) < 22 or len(fields[0]) != 1 or not fields[0].isascii() or not fields[0].isalpha():
        raise ValueError("Incomplete process stat")
    return {
        "pid": pid,
        "name": clean(text[opening + 1:closing]) or "Process",
        "stateCode": fields[0],
        "parent": nonnegative(fields[1]),
        "ticks": nonnegative(fields[11]) + nonnegative(fields[12]),
        "threads": nonnegative(fields[17]),
        "startTime": str(nonnegative(fields[19])),
        # Kernel RSS can briefly be negative during process teardown.
        "rssPages": max(0, int(fields[21])),
    }


def parse_status(text: str) -> tuple[int, tuple[int, ...]]:
    for line in text.splitlines():
        if line.startswith("Uid:"):
            values = tuple(nonnegative(v) for v in line.split()[1:])
            if len(values) != 4:
                raise ValueError("Invalid process owner")
            return values[1], values
    raise ValueError("Missing process owner")


def parse_io(text: str) -> tuple[int, int] | None:
    counters = {}
    for line in text.splitlines():
        key, separator, value = line.partition(":")
        if separator and key in {"read_bytes", "write_bytes"}:
            counters[key] = nonnegative(value.strip())
    if len(counters) != 2:
        return None
    return counters["read_bytes"], counters["write_bytes"]


def rate(current: int | None, previous: int | None, elapsed: float) -> float | None:
    if current is None or previous is None or elapsed <= 0 or current < previous:
        return None
    return round((current - previous) / elapsed, 2)


def cpu_share(current: int, previous: int | None, total_delta: int | None) -> float | None:
    if previous is None or total_delta is None or total_delta <= 0 or current < previous:
        return None
    return round(max(0.0, min(100.0, 100.0 * (current - previous) / total_delta)), 2)


class ProcReader:
    def __init__(self, proc: Path = Path("/proc"), sysfs: Path = Path("/sys"),
                 uid: int | None = None, own_pid: int | None = None):
        self.proc = Path(proc)
        self.sysfs = Path(sysfs)
        self.uid = os.getuid() if uid is None else uid
        self.own_pid = os.getpid() if own_pid is None else own_pid
        self.page_size = os.sysconf("SC_PAGE_SIZE")
        self.usernames: dict[int, str] = {}

    def username(self, uid: int) -> str:
        if uid not in self.usernames:
            try:
                value = clean(pwd.getpwuid(uid).pw_name, 32)
            except KeyError:
                value = str(uid)
            if len(self.usernames) > 256:
                self.usernames.clear()
            self.usernames[uid] = value
        return self.usernames[uid]

    def ancestry(self) -> set[int]:
        ancestors = {1, self.own_pid}
        current = self.own_pid
        for _ in range(64):
            try:
                parent = parse_stat(read_text(self.proc / str(current) / "stat", 8192), current)["parent"]
            except (OSError, ValueError):
                break
            if parent <= 1 or parent in ancestors:
                ancestors.add(parent)
                break
            ancestors.add(parent)
            current = parent
        return ancestors

    def read_process(self, pid: int, protected_pids: set[int] | None = None) -> dict[str, Any]:
        directory = self.proc / str(pid)
        record = parse_stat(read_text(directory / "stat", 8192), pid)
        uid, uids = parse_status(read_text(directory / "status"))
        record["uid"], record["uids"] = uid, uids
        try:
            # Only the executable basename is examined; paths/arguments are not
            # sent to the UI or retained in the sample history.
            executable = Path(os.readlink(directory / "exe")).name.removesuffix(" (deleted)")
        except OSError:
            executable = ""
        names = {record["name"].casefold(), executable.casefold()}
        reason = ""
        if pid <= 1 or pid in (protected_pids if protected_pids is not None else self.ancestry()):
            reason = "This process keeps Task Manager or your session running."
        elif any(owner != self.uid for owner in uids):
            reason = "Only your own processes can be ended."
        elif names & PROTECTED_NAMES:
            reason = "This process keeps your desktop running."
        elif record["stateCode"] in {"Z", "X", "x"}:
            reason = "This process has already exited."
        elif not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
            reason = "Safe process termination is unavailable on this system."
        record["canEnd"], record["protectedReason"] = not reason, reason
        try:
            record["io"] = parse_io(read_text(directory / "io", 8192))
        except (OSError, ValueError):
            record["io"] = None
        # Discard a process that exited or was reused during these reads.
        final = parse_stat(read_text(directory / "stat", 8192), pid)
        if final["startTime"] != record["startTime"]:
            raise ValueError("Process identity changed")
        return record

    def cpu(self) -> tuple[int, int, int]:
        lines = read_text(self.proc / "stat", 1024 * 1024).splitlines()
        if not lines or not lines[0].startswith("cpu "):
            raise ValueError("Missing CPU counters")
        counters = [nonnegative(value) for value in lines[0].split()[1:]]
        if len(counters) < 4:
            raise ValueError("Incomplete CPU counters")
        # guest and guest_nice (positions 8/9) are included in user/nice already.
        total = sum(counters[:8])
        idle = counters[3] + (counters[4] if len(counters) > 4 else 0)
        count = sum(line.startswith("cpu") and len(line) > 3 and line[3].isdigit() for line in lines)
        return total, idle, max(1, count)

    def memory(self) -> dict[str, int]:
        counters = {}
        for line in read_text(self.proc / "meminfo").splitlines():
            key, separator, values = line.partition(":")
            if separator and values.strip():
                counters[key] = nonnegative(values.split()[0]) * 1024
        total = counters.get("MemTotal", 0)
        if total <= 0:
            raise ValueError("Missing memory counters")
        available = counters.get("MemAvailable")
        if available is None:
            available = sum(counters.get(key, 0) for key in ("MemFree", "Buffers", "Cached", "SReclaimable"))
            available -= counters.get("Shmem", 0)
        swap = counters.get("SwapTotal", 0)
        return {
            "memoryTotal": total,
            "memoryUsed": max(0, min(total, total - available)),
            "swapTotal": swap,
            "swapUsed": max(0, min(swap, swap - counters.get("SwapFree", 0))),
        }

    def network(self) -> tuple[int, int] | None:
        try:
            rx = tx = count = 0
            for line in read_text(self.proc / "net/dev", 1024 * 1024).splitlines():
                interface, separator, values = line.rpartition(":")
                if not separator or interface.strip() == "lo":
                    continue
                fields = values.split()
                if len(fields) < 16:
                    continue
                rx += nonnegative(fields[0])
                tx += nonnegative(fields[8])
                count += 1
            return (rx, tx) if count else None
        except (OSError, ValueError):
            return None

    def disk(self) -> tuple[int, int] | None:
        try:
            physical = {path.name for path in (self.sysfs / "block").iterdir()
                        if not path.name.startswith(("loop", "ram", "zram", "dm-", "md"))}
            read = written = count = 0
            for line in read_text(self.proc / "diskstats", 1024 * 1024).splitlines():
                fields = line.split()
                if len(fields) >= 14 and fields[2] in physical:
                    read += nonnegative(fields[5]) * 512
                    written += nonnegative(fields[9]) * 512
                    count += 1
            return (read, written) if count else None
        except (OSError, ValueError):
            return None

    def uptime(self) -> float:
        try:
            value = float(read_text(self.proc / "uptime", 256).split()[0])
            return round(value, 1) if value >= 0 and math.isfinite(value) else 0.0
        except (OSError, ValueError, IndexError):
            return 0.0

    def pids(self) -> list[int]:
        return sorted(int(path.name) for path in self.proc.iterdir()
                      if path.name.isascii() and path.name.isdecimal() and 0 < int(path.name) <= 2147483647)[:MAX_PROCESSES]


class Sampler:
    def __init__(self, reader: ProcReader | None = None, clock=time.monotonic):
        self.reader = reader or ProcReader()
        self.clock = clock
        self.previous: dict[str, Any] | None = None
        self.previous_processes: dict[str, dict[str, Any]] = {}

    def sample(self) -> dict[str, Any]:
        now = self.clock()
        total, idle, count = self.reader.cpu()
        memory = self.reader.memory()
        network, disk = self.reader.network(), self.reader.disk()
        previous = self.previous
        elapsed = now - previous["time"] if previous else 0.0
        total_delta = total - previous["total"] if previous and total >= previous["total"] else None
        idle_delta = idle - previous["idle"] if previous and idle >= previous["idle"] else None
        if total_delta is not None and total_delta > 0 and idle_delta is not None:
            cpu = round(max(0.0, min(100.0, 100 * (total_delta - idle_delta) / total_delta)), 2)
        else:
            cpu = None
        def aggregate_rate(kind: str, counters: tuple[int, int] | None, index: int) -> float | None:
            old = previous[kind] if previous else None
            return rate(counters[index] if counters else None, old[index] if old else None, elapsed)
        system = {
            "cpuPercent": cpu, **memory, "uptime": self.reader.uptime(), "cpuCount": count,
            "netRxRate": aggregate_rate("network", network, 0),
            "netTxRate": aggregate_rate("network", network, 1),
            "diskReadRate": aggregate_rate("disk", disk, 0),
            "diskWriteRate": aggregate_rate("disk", disk, 1),
        }
        rows, current_processes = [], {}
        protected_pids = self.reader.ancestry()
        for pid in self.reader.pids():
            try:
                process = self.reader.read_process(pid, protected_pids)
            except (OSError, ValueError, IndexError):
                continue
            key = str(pid) + ":" + process["startTime"]
            old = self.previous_processes.get(key)
            io = process["io"]
            old_io = old["io"] if old else None
            rows.append({
                "key": key, "pid": pid, "startTime": process["startTime"],
                "name": process["name"], "user": self.reader.username(process["uid"]),
                "uid": process["uid"],
                "cpuPercent": cpu_share(process["ticks"], old["ticks"] if old else None, total_delta),
                "memoryBytes": process["rssPages"] * self.reader.page_size,
                "diskReadRate": rate(io[0] if io else None, old_io[0] if old_io else None, elapsed),
                "diskWriteRate": rate(io[1] if io else None, old_io[1] if old_io else None, elapsed),
                "state": STATE_NAMES.get(process["stateCode"], "Unknown"), "threads": process["threads"],
                "canEnd": process["canEnd"], "protectedReason": process["protectedReason"],
            })
            # Keep only counters and stable identities, never a command history.
            current_processes[key] = {"ticks": process["ticks"], "io": io}
        self.previous = {"time": now, "total": total, "idle": idle, "network": network, "disk": disk}
        self.previous_processes = current_processes
        return {"schema": 1, "system": system, "processes": rows}


def end_process(pid: int, start_time: str, reader: ProcReader | None = None) -> dict[str, Any]:
    """End one exact, same-user process. Never fall back to an unsafe os.kill."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1 or pid > 2147483647:
        return {"ok": False, "error": "Invalid process identity."}
    if not isinstance(start_time, str) or not 1 <= len(start_time) <= 20 or not start_time.isascii() or not start_time.isdecimal() or not 0 < int(start_time) < 2**64:
        return {"ok": False, "error": "Invalid process identity."}
    if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
        return {"ok": False, "error": "Safe process termination is unavailable on this system."}
    reader = reader or ProcReader()
    descriptor = None
    try:
        # Opening first makes subsequent exit/PID reuse harmless: SIGTERM is
        # always delivered through this original process reference, never PID.
        descriptor = os.pidfd_open(pid, 0)
        process = reader.read_process(pid)
        if process["startTime"] != start_time:
            return {"ok": False, "error": "Process identity changed. Select it again."}
        if not process["canEnd"]:
            return {"ok": False, "error": process["protectedReason"]}
        signal.pidfd_send_signal(descriptor, signal.SIGTERM, None, 0)
        return {"ok": True}
    except ProcessLookupError:
        return {"ok": False, "error": "This process is no longer running."}
    except PermissionError:
        return {"ok": False, "error": "You do not have permission to end this process."}
    except (FileNotFoundError, ValueError):
        return {"ok": False, "error": "This process changed or is no longer running."}
    except OSError:
        return {"ok": False, "error": "The process could not be ended safely."}
    finally:
        if descriptor is not None:
            os.close(descriptor)


def emit(value: dict[str, Any]) -> None:
    print(json.dumps(value, ensure_ascii=True, separators=(",", ":"), allow_nan=False), flush=True)


def watch() -> int:
    signal.signal(signal.SIGTERM, lambda _signal, _frame: sys.exit(0))
    signal.signal(signal.SIGINT, lambda _signal, _frame: sys.exit(0))
    sampler = Sampler()
    while True:
        started = time.monotonic()
        try:
            emit(sampler.sample())
        except (OSError, ValueError):
            emit({"schema": 1, "error": "System usage is temporarily unavailable."})
        deadline = started + INTERVAL
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                ready, _, _ = select.select([sys.stdin.fileno()], [], [], remaining)
                if ready and not os.read(sys.stdin.fileno(), 4096):
                    return 0
            except (OSError, ValueError):
                return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--watch", action="store_true")
    modes.add_argument("--once", action="store_true")
    modes.add_argument("--end", nargs=2, metavar=("PID", "STARTTIME"))
    args = parser.parse_args()
    if args.end:
        try:
            pid = int(args.end[0]) if args.end[0].isascii() and args.end[0].isdecimal() else 0
        except ValueError:
            pid = 0
        result = end_process(pid, args.end[1])
        emit(result)
        return 0 if result["ok"] else 2
    if args.watch:
        return watch()
    try:
        emit(Sampler().sample())
        return 0
    except (OSError, ValueError):
        emit({"schema": 1, "error": "System usage is temporarily unavailable."})
        return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        # A closed UI must not leave a worker attempting to print or retry.
        try:
            sys.stdout.close()
        except BrokenPipeError:
            pass
        raise SystemExit(0)
