# gRPC-over-Wine localhost diagnostics

Reusable, open-source reproducers built while diagnosing why the **EA app**
(EADesktop) never connects to its Background Service (EABackgroundService) over
its local gRPC channel under Wine on Apple Silicon - the long-standing "stub
invalid" wall.

## TL;DR - what these proved (2026-07-22)

The wall is **NOT** Wine's winsock/IOCP transport, it is **NOT** a
connect-completion/IOCP bug (the theory we'd carried for several sessions), and
it is **NOT** a Wine name-resolution bug either. **Every** Windows networking
primitive gRPC can use - transport *and* every resolver path - works correctly
under our patched Wine 11 (CrossOver-26 LGPL build). 12 checks, all green:

| Test | Primitive | Result under Wine 11 |
|------|-----------|----------------------|
| `01-connectex-iocp.c` | overlapped `ConnectEx` + IOCP completion (localhost) | ✅ completion posted |
| `02-acceptex-connectex-postconnect.c` | `AcceptEx`+`ConnectEx` + `SO_UPDATE_*_CONTEXT`, `SO_ERROR`, `getpeername` | ✅ all succeed |
| `03-overlapped-wsasend-wsarecv.c` | overlapped `WSASend`/`WSARecv` both directions | ✅ data flows |
| `04-pqcs-wsagetoverlappedresult.c` | `PostQueuedCompletionStatus` kick + `WSAGetOverlappedResult` | ✅ both work |
| `05-getaddrinfo-localhost.c` | `getaddrinfo("localhost")` | ✅ instant → 127.0.0.1 / ::1 |
| `06-wine-reported-dns-servers.c` | `GetNetworkParams` DNS server list | ✅ reports LAN router |
| `07-cares-getaddrinfo-localhost.c` | **c-ares** `ares_getaddrinfo("localhost")` | ✅ 8ms → 127.0.0.1 / ::1 (reads hosts) |
| `08-cares-raw-query-localhost.c` | **c-ares** raw `ares_query` A/AAAA (old-gRPC style) | ✅ ~2s (DNS, 1 retry) |
| `09-getaddrinfoexw-sync-async.c` | `GetAddrInfoExW` sync **and** async(overlapped+APC) | ✅ 3ms / 1ms |
| `10-overlapped-udp-recvfrom-iocp.c` | overlapped `WSARecvFrom` (UDP) via IOCP + 0-byte probe | ✅ datagram delivered |

## The actual conclusion

EADesktop talks to BGS on `localhost:<port>` via gRPC. The channel goes
`IDLE -> CONNECTING (started resolving, OK)` and then **never advances** - no
`tcp`/`http` tracer activity ever appears; it is stuck in the resolve step
*forever* (observed 5+ min; retries every 5 min, never succeeds) and EA logs
`Can't create unary request … [stub invalid]`.

Yet under the *same* Wine bottle, isolated tests show c-ares resolves
`localhost` (both via `ares_getaddrinfo` and raw `ares_query`), `getaddrinfo`
resolves it, and `GetAddrInfoExW` (sync + async) resolves it - and every
IOCP/overlapped socket primitive works, including the overlapped-UDP-recv trick
gRPC's `grpc_polled_fd_windows` uses to drive c-ares under IOCP.

**So there is no broken Wine primitive to patch.** The hang lives inside gRPC's
own orchestration - how its EventEngine/poller schedules and drives the resolver
work item - as compiled into `EADesktop.exe`. It reproduces only when gRPC's
actual code runs under Wine, not with any isolated primitive, so it cannot be
isolated or fixed from Wine's side without EA's exact gRPC sources + symbols
(and even then the fix would be in EA's static binary, not Wine).

Things also ruled out: `GRPC_DNS_RESOLVER=native` (no effect); adding
`HKLM\...\Tcpip\Parameters\NameServer` (no effect); the bottle hosts file +
`DataBasePath` are already correct and c-ares reads them fine in isolation.

## Realistic paths for an EA client on Uncork

1. **Origin** (EA's pre-2022 client): monolithic, **no `EABackgroundService` /
   no localhost gRPC**, long proven under Wine/CrossOver - the only clean way to
   get an EA client working today. (Caveat: EA is deprecating Origin downloads.)
2. Track CrossOver's *proprietary* EA support (25.1.0+), which works and whose
   fix is almost certainly NOT in the LGPL source.
3. Park EA; ship Ubisoft (the CEF win) + the other launchers.

Downgrading the *EA app* itself does not help - every EA app build uses the same
EADesktop↔BGS gRPC handshake.

Ubisoft Connect (the other CEF launcher) is unaffected and remains the shipped
CEF win - see memory `cef-32bit-d3dmetal-wall`.

## Build + run

```sh
# from repo root; needs mingw (brew) + a built Wine engine
bash wine-fixes/diagnostics/grpc-localhost/run.sh
```
Each test self-terminates and prints a clear PASS/FAIL line.
