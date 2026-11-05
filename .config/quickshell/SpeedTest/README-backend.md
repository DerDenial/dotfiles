# Explicit HTTP speed test

`python3 run.py` performs one test and exits. Importing the module does not start
threads or requests. The panel must launch it only after the user presses Start.
There is no idle worker, package installation, credential, history file, result
submission, geolocation request or automatic background test.

## Transport and scope

The only remote host is `speed.cloudflare.com`, over certificate-verified HTTPS:
GET `/__down?bytes=N` downloads test bytes; POST `/__up?bytes=N` uploads the
specified request body. These endpoints and request methods are described by
Cloudflare's own open-source speed-test project. No Authorization header is sent.
The helper does not use the browser engine, its result logging, TURN service or
packet-loss features.

This is a bounded HTTP throughput test to Cloudflare's edge, not an ISP line-rate
certificate or the complete Cloudflare speed-test methodology. Wi-Fi, VPNs,
congestion, server distance, HTTP/1.1 overhead, the payload cap and the machine
itself can affect the result. It does not infer a speed from local link counters.

## Measurements

- One HTTPS connection is warmed before six unloaded latency samples.
  `latencyMs` is their median HTTP response-header round trip, excluding initial
  DNS/TCP/TLS setup. Server processing is included. This is HTTP latency, not ICMP.
- `jitterMs` is the mean absolute difference between successive latency samples.
- Download and upload each use up to three workers for six seconds, ending early
  if their payload budget is exhausted. Aggregate rates divide bytes transferred
  by the common phase wall time, including initial connection setup and HTTP
  overhead; simultaneous worker rates are never averaged or summed twice.
- Live upload uses bytes successfully passed to the socket. Final upload uses
  only request bodies acknowledged by a successful server response, so a stalled
  or rejected upload cannot produce a successful result from kernel buffering.
- Download requests reserve up to 10 MB each. Upload requests start at 64 KiB and
  adapt up to 2 MB, so slow links can confirm a short sample before the deadline.
- Download has a 150,000,000-byte reservation budget, upload 100,000,000 bytes.
  Therefore test payload is at most **250 MB**, plus small HTTP/TLS overhead and
  endpoint response bodies. Atomic reservations enforce the cap across workers.
- Each phase is bounded; the whole helper has a 24-second deadline. Per-operation
  timeouts and socket shutdown interrupt stalled transfers. DNS resolution can
  remain blocked in a daemon worker, which cannot keep the helper process alive.
- SIGTERM/SIGINT only set a cancellation flag. Main-loop cleanup closes owned
  sockets outside the signal handler. No other process or connection is killed.

## JSON lines

Each stdout line is a complete snapshot, flushed immediately. Normal telemetry
is coalesced to five updates per second; phase boundaries and the terminal state
are sent immediately. Keys are:

```json
{
  "phase": "download",
  "progress": 0.3,
  "downloadMbps": null,
  "uploadMbps": null,
  "latencyMs": 14.2,
  "jitterMs": 1.1,
  "liveMbps": 92.4,
  "bytesTransferred": 12000000,
  "provider": "Cloudflare",
  "error": "",
  "elapsed": 2.4
}
```

Phases are `latency`, `download`, `upload`, `complete`, `error`, `cancelled`.
Progress is 0–1. Rates use decimal Mbps. Missing/unmeasured results are null, not
fabricated zeroes. Terminal `error` carries a short English message; underlying
network error details are not included. Cancellation exits successfully with a
cancelled state. A test error exits with status 1. No CLI arguments are accepted.

## Verification

18 deterministic tests use fake HTTP connections/transports and bounded worker
threads. They cover request/TLS setup, payload accounting and budgets, aggregate
rates, latency/jitter, malformed/server-error responses, cancellation, cleanup,
progress snapshots and missing upload confirmation. A separate owned-process
fixture exercises the production SIGTERM handler with an inert stalled transport
and confirms prompt cancellation without opening any network socket. No actual
speed test, packet capture or desktop action was performed during development.

Commands, relative to the staged package:

```sh
python3 tests/backend/test_run.py
python3 tests/backend/signal_cancel.py
```

Primary references checked during implementation:

- https://github.com/cloudflare/speedtest/blob/main/README.md
- https://github.com/cloudflare/speedtest/blob/main/src/engines/BandwidthEngine/BandwidthEngine.ts
