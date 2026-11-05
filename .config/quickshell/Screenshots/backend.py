#!/usr/bin/env python3
"""Private screenshot capture and explicit rasterized copy/save actions."""

import argparse
import ctypes
from datetime import datetime
import io
import json
import math
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import time
import uuid

from PIL import Image, ImageDraw


MAX_PIXELS = 32_000_000
MAX_DIMENSION = 16_384
MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_OPERATIONS = 64
MAX_POINTS = 120_000
Image.MAX_IMAGE_PIXELS = MAX_PIXELS
TOKEN = re.compile(r"^[a-f0-9]{32}$")
GEOMETRY = re.compile(r"^(-?\d+),(-?\d+)\s+(\d+)x(\d+)$")
COLOR = re.compile(r"^#[a-fA-F0-9]{6}$")
KNOWN_FILES = {"original.png", "metadata.json"}
_child = None
_freezer = None
_unfinished = None


class BackendError(Exception):
    pass


class Cancelled(Exception):
    pass


def plain_text(value, maximum=256):
    return re.sub(r"[\x00-\x1f\x7f]", " ", str(value))[:maximum].strip()


def app_basename(value):
    value = "".join(character if character.isalnum() or character in ".-_" else "_"
                    for character in plain_text(value))
    value = re.sub(r"_+", "_", value).strip("._-")
    while len(value.encode("utf-8")) > 80:
        value = value[:-1]
    return value or "Screenshot"


def private_directory(path, create=False):
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        information = path.lstat()
    except OSError as error:
        raise BackendError("The screenshot session is unavailable.") from error
    if not stat.S_ISDIR(information.st_mode) or information.st_uid != os.getuid():
        raise BackendError("The screenshot session is unavailable.")
    if information.st_mode & 0o077:
        if create:
            path.chmod(0o700)
        else:
            raise BackendError("The screenshot session is unavailable.")
    return path


def session_base(create=False):
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid())))
    if not runtime.is_absolute():
        raise BackendError("A desktop session is required.")
    private_directory(runtime)
    return private_directory(runtime / "quickshell-screenshots", create)


def session_directory(token):
    if not isinstance(token, str) or not TOKEN.fullmatch(token):
        raise BackendError("The screenshot session is unavailable.")
    return private_directory(session_base() / ("session-" + token))


def safe_remove(directory):
    """Remove only our known files, never recursively follow arbitrary entries."""
    try:
        private_directory(directory)
        for name in KNOWN_FILES:
            path = directory / name
            try:
                information = path.lstat()
                if information.st_uid == os.getuid() and not stat.S_ISDIR(information.st_mode):
                    path.unlink()
            except FileNotFoundError:
                pass
        directory.rmdir()
    except (OSError, BackendError):
        pass


def prune_stale(base):
    cutoff = time.time() - 6 * 60 * 60
    try:
        children = list(base.iterdir())
    except OSError:
        return
    for directory in children:
        if not directory.name.startswith("session-") or not TOKEN.fullmatch(directory.name[8:]):
            continue
        try:
            information = directory.lstat()
            if stat.S_ISDIR(information.st_mode) and information.st_uid == os.getuid() and information.st_mtime < cutoff:
                safe_remove(directory)
        except OSError:
            pass


def child_parent_guard(parent_pid, death_signal=signal.SIGTERM):
    # Ensure a killed/reloaded capture helper cannot leave the slurp layer open.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, death_signal, 0, 0, 0) != 0:
        os._exit(126)
    if os.getppid() != parent_pid:
        os._exit(125)


def stop_process(process):
    """Stop and reap only a child owned by this capture helper."""
    if process is None or process.poll() is not None:
        return
    try:
        process.terminate()
        process.wait(timeout=0.3)
    except (OSError, subprocess.TimeoutExpired):
        try:
            process.kill()
            process.wait(timeout=0.3)
        except (OSError, subprocess.TimeoutExpired):
            pass


def stop_freezer():
    global _freezer
    process, _freezer = _freezer, None
    stop_process(process)


def require_freezer():
    if _freezer is None or _freezer.poll() is not None:
        raise BackendError("Screen freezing stopped. Please try the screenshot again.")


def start_freezer():
    global _freezer
    parent_pid = os.getpid()
    try:
        _freezer = subprocess.Popen(
            ["hyprpicker", "-r", "-z", "-d"], stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            preexec_fn=lambda: child_parent_guard(parent_pid, signal.SIGKILL),
        )
    except OSError as error:
        raise BackendError("Screen freezing is unavailable. Install hyprpicker and try again.") from error
    # hyprpicker has no public frame-ready notification. This short settling
    # interval follows the established hyprshot approach; it is not a frame ACK.
    deadline = time.monotonic() + 0.25
    while time.monotonic() < deadline:
        require_freezer()
        time.sleep(min(0.025, max(0, deadline - time.monotonic())))
    require_freezer()


def run_capture_child(command, *, capture_output=False, timeout=None, monitor_freezer=False):
    global _child
    parent_pid = os.getpid()
    _child = subprocess.Popen(
        command, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE if capture_output else subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=lambda: child_parent_guard(parent_pid),
    )
    deadline = time.monotonic() + timeout if timeout is not None else None
    try:
        while True:
            if monitor_freezer:
                require_freezer()
            remaining = max(0, deadline - time.monotonic()) if deadline is not None else None
            wait = min(0.1, remaining) if monitor_freezer and remaining is not None else 0.1 if monitor_freezer else remaining
            try:
                output, _ = _child.communicate(timeout=wait)
                if monitor_freezer:
                    require_freezer()
                return _child.returncode, output or b""
            except subprocess.TimeoutExpired as error:
                if not monitor_freezer or deadline is not None and time.monotonic() >= deadline:
                    raise BackendError("The selected area could not be captured.") from error
    except BaseException:
        stop_process(_child)
        raise
    finally:
        _child = None


def cancel(signum, frame):
    stop_process(_child)
    stop_freezer()
    raise Cancelled()


def write_private(path, content):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(content)


def read_private(path, maximum):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as source:
        information = os.fstat(source.fileno())
        if not stat.S_ISREG(information.st_mode) or information.st_uid != os.getuid() or information.st_size > maximum:
            raise BackendError("The screenshot session is unavailable.")
        return source.read(maximum + 1)


def image_dimensions(path):
    data = read_private(path, 64 * 1024 * 1024)
    with Image.open(io.BytesIO(data)) as image:
        width, height = image.size
        if image.format != "PNG" or width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION or width * height > MAX_PIXELS:
            raise BackendError("The selected area is too large.")
        image.verify()
        return width, height


def capture_region(app_name):
    global _unfinished
    base = session_base(create=True)
    prune_stale(base)
    token = uuid.uuid4().hex
    directory = base / ("session-" + token)
    directory.mkdir(mode=0o700)
    _unfinished = directory
    captured_at = datetime.now().astimezone()
    try:
        start_freezer()
        code, output = run_capture_child(["slurp", "-d"], capture_output=True, monitor_freezer=True)
        if code != 0:
            raise Cancelled()
        try:
            geometry = output.decode("ascii").strip()
        except UnicodeError as error:
            raise BackendError("The selected area could not be captured.") from error
        match = GEOMETRY.fullmatch(geometry)
        if not match:
            raise BackendError("The selected area could not be captured.")
        x, y, selected_width, selected_height = map(int, match.groups())
        if selected_width < 1 or selected_height < 1 or selected_width > MAX_DIMENSION or selected_height > MAX_DIMENSION:
            raise BackendError("The selected area is too large.")
        original = directory / "original.png"
        code, _ = run_capture_child(["grim", "-g", geometry, str(original)], timeout=15, monitor_freezer=True)
        if code != 0:
            raise BackendError("The selected area could not be captured.")
        require_freezer()
        original.chmod(0o600)
        width, height = image_dimensions(original)
        metadata = {"appName": plain_text(app_name) or "Screenshot", "basename": app_basename(app_name),
                    "capturedAt": captured_at.isoformat(), "timestamp": captured_at.strftime("%Y-%m-%d_%H-%M-%S")}
        write_private(directory / "metadata.json", json.dumps(metadata, ensure_ascii=True).encode("utf-8"))
        result = {"ok": True, "session": token, "path": str(original), "url": original.as_uri(),
                  "width": width, "height": height, "appName": metadata["appName"], "capturedAt": metadata["capturedAt"],
                  "x": x, "y": y, "geometry": {"x": x, "y": y, "width": selected_width, "height": selected_height}}
    finally:
        stop_freezer()
    # Publish the session only after the frozen layer has been removed. A
    # cancellation during that handoff must still clean the private image.
    _unfinished = None
    return result


def number(value, *, default=None):
    if value is None and default is not None:
        return default
    if isinstance(value, bool) or not isinstance(value, (int, float)) or abs(value) > 1_000_000 or not math.isfinite(value):
        raise BackendError("The edits could not be applied.")
    return float(value)


def rgba(value, opacity=1):
    if not isinstance(value, str) or not COLOR.fullmatch(value):
        raise BackendError("The selected color is invalid.")
    return tuple(int(value[index:index + 2], 16) for index in (1, 3, 5)) + (round(max(0, min(1, opacity)) * 255),)


def bounds(operation, width, height):
    x, y = number(operation.get("x")), number(operation.get("y"))
    w, h = number(operation.get("width")), number(operation.get("height"))
    left, right = sorted((x, x + w))
    top, bottom = sorted((y, y + h))
    return (max(0, min(width, math.floor(left))), max(0, min(height, math.floor(top))),
            max(0, min(width, math.ceil(right))), max(0, min(height, math.ceil(bottom))))


def render_image(original, edit):
    if not isinstance(edit, dict) or not isinstance(edit.get("operations", []), list):
        raise BackendError("The edits could not be applied.")
    operations = edit.get("operations", [])
    if len(operations) > MAX_OPERATIONS:
        raise BackendError("There are too many edits. Please undo a few strokes.")
    source = read_private(original, 64 * 1024 * 1024)
    with Image.open(io.BytesIO(source)) as decoded:
        width, height = decoded.size
        if decoded.format != "PNG" or width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION or width * height > MAX_PIXELS:
            raise BackendError("The selected area is too large.")
        image = decoded.convert("RGBA")
    points_seen = 0
    for operation in operations:
        if not isinstance(operation, dict):
            raise BackendError("The edits could not be applied.")
        kind = operation.get("type")
        if kind == "pen":
            raw_points = operation.get("points")
            if not isinstance(raw_points, list) or not raw_points or len(raw_points) > 4000:
                raise BackendError("The pen stroke could not be applied.")
            points_seen += len(raw_points)
            if points_seen > MAX_POINTS:
                raise BackendError("There are too many edits. Please undo a few strokes.")
            points = [(max(0, min(width, number(point.get("x")))), max(0, min(height, number(point.get("y")))))
                      for point in raw_points if isinstance(point, dict)]
            if len(points) != len(raw_points):
                raise BackendError("The pen stroke could not be applied.")
            stroke = max(1, min(80, round(number(operation.get("width"), default=4))))
            color = rgba(operation.get("color", "#ffffff"))
            draw = ImageDraw.Draw(image)
            draw.line(points, fill=color, width=stroke, joint="curve")
            radius = stroke / 2
            for x, y in (points[0], points[-1]):
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)
        elif kind in ("highlight", "pixelate", "rect", "arrow"):
            left, top, right, bottom = bounds(operation, width, height)
            if kind != "arrow" and (right <= left or bottom <= top):
                continue
            if kind == "highlight":
                opacity = max(0, min(0.8, number(operation.get("opacity"), default=0.32)))
                tile = Image.new("RGBA", (right - left, bottom - top), rgba(operation.get("color", "#ffff00"), opacity))
                image.alpha_composite(tile, (left, top))
            elif kind == "pixelate":
                block = max(4, min(80, round(number(operation.get("blockSize"), default=16))))
                pixels = image.load()
                draw = ImageDraw.Draw(image)
                for y in range(top, bottom, block):
                    y1 = min(bottom, y + block)
                    for x in range(left, right, block):
                        x1 = min(right, x + block)
                        color = pixels[x + (x1 - x) // 2, y + (y1 - y) // 2]
                        draw.rectangle((x, y, x1 - 1, y1 - 1), fill=color)
            elif kind == "rect":
                stroke = max(1, min(80, round(number(operation.get("strokeWidth"), default=4))))
                ImageDraw.Draw(image).rectangle((left, top, right - 1, bottom - 1),
                                                outline=rgba(operation.get("color", "#ffffff")), width=stroke)
            else:
                raw_start = (number(operation.get("x")), number(operation.get("y")))
                start = (max(0, min(width, raw_start[0])), max(0, min(height, raw_start[1])))
                end = (max(0, min(width, raw_start[0] + number(operation.get("width")))),
                       max(0, min(height, raw_start[1] + number(operation.get("height")))))
                stroke = max(1, min(80, round(number(operation.get("strokeWidth"), default=4))))
                color = rgba(operation.get("color", "#ffffff"))
                draw = ImageDraw.Draw(image)
                draw.line((start, end), fill=color, width=stroke)
                angle = math.atan2(end[1] - start[1], end[0] - start[0])
                head = min(math.dist(start, end), max(12, stroke * 4))
                draw.polygon((end, (end[0] - head * math.cos(angle - 0.5), end[1] - head * math.sin(angle - 0.5)),
                              (end[0] - head * math.cos(angle + 0.5), end[1] - head * math.sin(angle + 0.5))), fill=color)
        else:
            raise BackendError("This edit tool is unavailable.")
    crop = edit.get("crop")
    if crop is not None:
        if not isinstance(crop, dict):
            raise BackendError("The crop could not be applied.")
        rectangle = bounds(crop, width, height)
        if rectangle[2] <= rectangle[0] or rectangle[3] <= rectangle[1]:
            raise BackendError("The crop is empty.")
        image = image.crop(rectangle)
    return image


def original_png(path):
    """Validate the native capture without converting or re-encoding its PNG."""
    data = read_private(path, 64 * 1024 * 1024)
    with Image.open(io.BytesIO(data)) as image:
        width, height = image.size
        if image.format != "PNG" or width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION or width * height > MAX_PIXELS:
            raise BackendError("The selected area is too large.")
        # Decode as render_image does, so an invalid pixel stream is not copied.
        image.load()
    return data, width, height


def save_png(metadata, writer, home=None):
    folder = (home or Path.home()) / "Pictures/Screenshots"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    prefix = app_basename(metadata.get("basename", "Screenshot"))
    timestamp = str(metadata.get("timestamp", ""))
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}", timestamp):
        timestamp = datetime.now().astimezone().strftime("%Y-%m-%d_%H-%M-%S")
    for suffix in range(1000):
        filename = prefix + "_" + timestamp + ("_" + str(suffix) if suffix else "") + ".png"
        path = folder / filename
        try:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            continue
        try:
            with os.fdopen(descriptor, "wb") as output:
                writer(output)
            return path
        except BaseException:
            path.unlink(missing_ok=True)
            raise
    raise BackendError("Please try saving the screenshot again.")


def save_image(image, metadata, home=None):
    return save_png(metadata, lambda output: image.save(output, format="PNG", compress_level=6), home)


def save_png_bytes(data, metadata, home=None):
    return save_png(metadata, lambda output: output.write(data), home)


def export(session, action, edit):
    directory = session_directory(session)
    try:
        metadata = json.loads(read_private(directory / "metadata.json", 8192))
    except (ValueError, UnicodeError) as error:
        raise BackendError("The screenshot session is unavailable.") from error
    if not isinstance(metadata, dict):
        raise BackendError("The screenshot session is unavailable.")
    # Only the well-formed, genuinely empty edit takes the byte-preserving path.
    # Malformed operations/crops still go through render_image's validation.
    unchanged = isinstance(edit, dict) and isinstance(edit.get("operations", []), list) \
        and not edit.get("operations", []) and edit.get("crop") is None
    if unchanged:
        png, width, height = original_png(directory / "original.png")
    else:
        image = render_image(directory / "original.png", edit)
        width, height = image.size
    result = {"ok": True, "action": action, "width": width, "height": height,
              "appName": plain_text(metadata.get("appName", "Screenshot"))}
    if action == "copy":
        if not unchanged:
            output = io.BytesIO()
            image.save(output, format="PNG", compress_level=6)
            png = output.getvalue()
        copied = subprocess.run(["wl-copy", "--type", "image/png"], input=png,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=12)
        if copied.returncode != 0:
            raise BackendError("The screenshot could not be copied.")
    else:
        result["path"] = str(save_png_bytes(png, metadata) if unchanged else save_image(image, metadata))
    return result


def read_edits():
    line = sys.stdin.buffer.readline(MAX_INPUT_BYTES + 1)
    if len(line) > MAX_INPUT_BYTES or not line:
        raise BackendError("The edits could not be read.")
    try:
        return json.loads(line)
    except (ValueError, UnicodeError) as error:
        raise BackendError("The edits could not be read.") from error


def main():
    global _unfinished
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("capture-region")
    capture.add_argument("--app-name", default="Screenshot")
    render = commands.add_parser("render")
    render.add_argument("--session", required=True)
    render.add_argument("--action", choices=("copy", "save"), required=True)
    cleanup = commands.add_parser("cleanup")
    cleanup.add_argument("--session", required=True)
    args = parser.parse_args()
    os.umask(0o077)
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    try:
        if args.command == "capture-region":
            result = capture_region(args.app_name)
        elif args.command == "render":
            result = export(args.session, args.action, read_edits())
        else:
            safe_remove(session_directory(args.session))
            result = {"ok": True}
    except Cancelled:
        result = {"ok": False, "cancelled": True}
    except BackendError as error:
        result = {"ok": False, "error": str(error)}
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError, Image.DecompressionBombError):
        result = {"ok": False, "error": "The screenshot action could not be completed."}
    finally:
        if _unfinished is not None:
            safe_remove(_unfinished)
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
