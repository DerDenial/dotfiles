#!/usr/bin/env python3
"""Discover a readable backlight once; QML then reads its brightness directly."""
import json
from pathlib import Path


def discover():
    candidates = []
    for device in sorted(Path("/sys/class/backlight").glob("*")):
        try:
            maximum = int((device / "max_brightness").read_text().strip())
            current = int((device / "brightness").read_text().strip())
            kind = (device / "type").read_text().strip()
            if maximum > 0:
                candidates.append((kind != "firmware", kind != "platform", str(device), {
                    "path": str(device / "brightness"),
                    "maximum": maximum,
                    "current": current,
                }))
        except (OSError, ValueError):
            continue
    return sorted(candidates, key=lambda entry: entry[:3])[0][3] if candidates else {}


if __name__ == "__main__":
    print(json.dumps(discover()))
