#!/usr/bin/env python3
"""Use logind's desktop power API without the separate terminal wall-message call."""
import argparse
import os
import sys

METHODS = {'poweroff': 'PowerOff', 'reboot': 'Reboot'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=METHODS)
    args = parser.parse_args()
    command = ['/usr/bin/busctl', '--system', '--allow-interactive-authorization=yes',
               'call', 'org.freedesktop.login1', '/org/freedesktop/login1',
               'org.freedesktop.login1.Manager', METHODS[args.action], 'b', 'true']
    # Replace this short-lived helper; logind still applies its normal policy
    # and application inhibitors. There is no privileged fallback.
    os.execv(command[0], command)


if __name__ == '__main__':
    try:
        main()
    except OSError as error:
        print('Systemaktion konnte nicht angefordert werden: ' + str(error), file=sys.stderr)
        sys.exit(1)
