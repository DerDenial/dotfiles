# On-demand connection check

`check.py` runs only when explicitly requested. It emits complete JSON objects,
one per line, and never changes Wi-Fi, routing, DNS, VPN, proxy, NetworkManager,
firewall or other settings. No worker remains after the helper exits. Results
are returned on stdout and are not saved by the backend.

## Contract

Every snapshot contains `phase`, `steps`, `summary` and `checkedAt`.

- `phase`: `running`, `complete`, `cancelled` or `error`.
- `steps`: exactly four ordered entries with IDs `link`, `router`, `dns`,
  `internet`. Each has `status`, `title`, `detail` and nullable `durationMs`.
- Step status: `pending`, `running`, `ok`, `warning`, `failed` or `skipped`.
- `summary`: `status`, `title`, `detail`. Terminal phases use statuses
  `ok|warning|failed` for complete, `cancelled` for cancellation, `error` for error.
- `checkedAt`: null during a run, UTC ISO timestamp when finished.

Error/cancellation output retains all four entries and marks unfinished entries
skipped. A failed diagnostic check is a complete diagnostic result, not a
process error. Process exit code 0 means complete/cancelled; 1 means the helper
could not finish.

## Checks and interpretation

1. **Network link:** local `ip -j address show`, requiring an enabled adapter
   with a usable non-loopback/non-link-local address; tentative addresses and
   down links are excluded. This is IP readiness rather than Wi-Fi signal quality.
2. **Router:** best available main-table gateway with a connected link, IPv4 or
   IPv6. One bounded, numeric ICMP echo is sent. No reply is a warning because
   routers/firewalls can block ping. No gateway is skipped: VPN and point-to-point
   paths can be valid without one. The gateway is explicitly a local-router
   check, not a claim about the actual VPN/policy-routed internet egress.
3. **DNS:** system NSS resolution for `speed.cloudflare.com`, in a bounded child.
   The system's existing resolver, including VPN DNS, is used unchanged. Failure
   for this single test name is not proof that every DNS query is broken.
4. **Internet:** a TLS-verified GET to
   `https://speed.cloudflare.com/__down?bytes=0` must return empty 200/204. The
   child connects directly to validated addresses from the preceding resolver
   result and retains the host's TLS SNI/hostname verification, so there is no
   hidden second blocking hostname lookup. Both IP families can be attempted.
   A small plain-HTTP check to Arch's installed NetworkManager endpoint,
   `http://ping.archlinux.org/nm-check.txt`, expects the standard online response
   header/body. Bodies are capped at 1025 bytes; oversized responses fail the
   expected-response test. Redirects are never followed or opened automatically.

A redirect/unexpected response is only a possible sign-in/filtering hint. TLS
failure alone is not called a captive portal. If secure access succeeds, a
blocked ping or unavailable plain-HTTP probe cannot declare the whole connection
offline. One unavailable test service is not proof that every site is offline.
If DNS fails, a bounded direct TCP connection to `1.1.1.1:443` or
`[2606:4700:4700::1111]:443` can support the qualified suggestion that DNS may be
the problem. These IP endpoints are Cloudflare, not user-supplied destinations.

Local kernel route queries for those fixed IPv4/IPv6 destinations include TCP
port 443 and policy routing (`ip route get`, not only main-table defaults). They
send no packets. The HTTP probes follow the OS-selected route and are never
bound to the physical interface selected by the separate passive traffic panel.
The result therefore may traverse a VPN. A destination-specific policy rule can
still make another website use a different route.

These direct diagnostics do not implement HTTP_PROXY/HTTPS_PROXY application
proxies. A proxy-required network can legitimately block direct test traffic;
wording qualifies failed probes and mentions proxy/filter/VPN possibilities.

## Contacts and bounds

An explicit run contacts only the local gateway, the existing system DNS
resolver for the two fixed test hostnames, Cloudflare and Arch's connectivity
endpoint. No window/app names, clipboard data, credentials, user files or stored
network history are sent. External endpoints naturally see the connection's
source IP. No speed-test payload or public result upload is generated.

DNS, HTTP and TCP operations run in short-lived owned subprocess modes. Even
blocking NSS resolution or trickling HTTP headers cannot bypass the parent
helper's 15-second deadline. SIGTERM/SIGINT handlers only set a cancellation
flag; the main loop terminates/reaps its known child, with a bounded SIGKILL
fallback. No process group, network service or unrelated process is targeted.

## Verification

- `tests/backend/test_check.py`: 23 mocked/local tests covering success, partial
  results, ping blocking, IPv6/VPN/no-gateway cases, bounded resolver/probes,
  verified TLS hostname, no second DNS lookup, redirect/oversized response,
  command argument safety, cancellation and owned-child timeout cleanup.
- `tests/backend/signal_cancel.py`: production SIGTERM handler with an inert
  stalled child; cancellation completed in about 43 ms and reaped that child.
- No real diagnostic/network probe was run during implementation. The execution
  environment's network namespace is isolated from the user's desktop.

Primary references:

- NetworkManager connectivity semantics and plain-HTTP expected response:
  https://networkmanager.dev/docs/api/latest/NetworkManager.conf.html
- `nmcli networking connectivity check` actively reruns checks; it is deliberately
  not used here: https://networkmanager.dev/docs/api/latest/nmcli
- The installed Arch endpoint matches `/usr/lib/NetworkManager/conf.d/20-connectivity.conf`:
  https://wiki.archlinux.org/title/NetworkManager#Checking_connectivity
- Cloudflare zero-byte download endpoint:
  https://github.com/cloudflare/speedtest
- Policy-route lookup semantics:
  https://man7.org/linux/man-pages/man8/ip-route.8.html
