"""Small process ownership helpers shared by the lock and idle launchers."""
import fcntl
import os
from pathlib import Path
import signal
import stat
import subprocess


def runtime_directory():
    base = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    info = base.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError("No private desktop runtime directory is available")
    folder = base / "quickshell-lockscreen"
    folder.mkdir(mode=0o700, exist_ok=True)
    info = folder.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError("Invalid lock screen runtime directory")
    folder.chmod(0o700)
    return folder


def claim(name):
    descriptor = os.open(runtime_directory() / name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(descriptor)
        return None
    os.set_inheritable(descriptor, False)
    return descriptor


def already_running(name):
    try:
        result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", name],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def supervise(command):
    # Keep ownership in this parent only; idle callbacks must not inherit its lock.
    child = None
    pending_signal = None

    def forward(number, frame):
        nonlocal pending_signal
        pending_signal = number
        if child is not None and child.poll() is None:
            try:
                child.send_signal(number)
            except ProcessLookupError:
                pass

    previous = {number: signal.signal(number, forward)
                for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    try:
        environment = os.environ.copy()
        environment.pop("WAYLAND_DEBUG", None)
        child = subprocess.Popen(command, close_fds=True, env=environment)
        if pending_signal is not None:
            forward(pending_signal, None)
        return child.wait()
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)
