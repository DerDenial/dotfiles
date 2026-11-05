#!/bin/sh
# Run from any directory. Python performs all validation before changing files.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec python3 "$script_dir/scripts/install.py" "$@"
