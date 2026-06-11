# Bug: Web build can't connect to validator: gateway rejects header-less WebSocket upgrade

**Status:** open

## Report
- **Component:** Validator Client (Godot net/validator_client.gd) ⇄ Snapser gateway / byosnap-validator (app c4n1awfs)
- **Platform:** Web (HTML5 / WebGL export); native desktop/mobile unaffected
- **Version:** First web build — commit 9fb6c8f; diagnosed 2026-06-11 against live gateway.snapser.com/c4n1awfs

## Summary
Story mode fails to connect in the web build: the browser's WebSocket upgrade to the deployed validator (wss://gateway.snapser.com/c4n1awfs/v1/byosnap-validator/socket.io/?EIO=4&transport=websocket) is rejected with HTTP 400 (seen client-side as WS close 1006).

Root cause: the Snapser gateway authenticates every forwarded request — including the WS upgrade — using the gateway-auth HTTP headers (Token / User-Id). The client sets these via WebSocketPeer.handshake_headers (net/validator_client.gd `_connect_socket`), which works on native but is SILENTLY IGNORED in Godot web exports because browsers forbid custom headers on a WebSocket handshake. So the upgrade reaches the gateway with no auth and is rejected.

This is NOT a 'gateway can't forward WS to an HTTP byosnap' problem — that path works (see Observed): a non-browser client that CAN set the headers completes the 101 upgrade to our HTTP/Socket.IO BYOSnap. The gap is purely that browsers have no way to present the token on a WS upgrade, and the gateway accepts no header-less alternative (query-string and Sec-WebSocket-Protocol both rejected).

Note: validate_action / complete_match exist ONLY over Socket.IO (the validator's HTTP routes are just init/history), so any fix must move validation onto an HTTP-based transport that carries the auth headers.

## Repro steps
1. Export/serve the Godot web build (e.g. http://localhost:51317/) — commit 9fb6c8f or later.
2. Open it in a browser and choose Story mode (which signs in to Snapser anonymously and targets the deployed validator BYOSnap).
3. Observe: connection fails. In DevTools → Network, the GET to wss://gateway.snapser.com/c4n1awfs/v1/byosnap-validator/socket.io/?EIO=4&transport=websocket returns 400 (WS closes with code 1006). The preceding HTTP /api/match/init returns 200.
4. Confirm it's the missing WS headers (not the byosnap): from a Bun script, anon-login then `new WebSocket(wssUrl, { headers: { Token, 'User-Id' } })` → 101 + `0{"sid":…}`. The same upgrade from a browser (which can't set headers) closes 1006. Query-string and Sec-WebSocket-Protocol token variants from the browser also close 1006.

## Expected result
In the web build, joining Story mode connects to the deployed validator and validates moves over the network, exactly as on native (HUD shows `validator: ✓ move N`).

## Observed result
Joining Story mode in the web build fails to connect. The WS upgrade GET returns HTTP 400 at the gateway (WS close code 1006); HTTP `/api/match/init` succeeds first (fetch carries headers fine), so init returns a connection_id but the subsequent socket never opens.

Verified live against gateway.snapser.com/c4n1awfs (2026-06-11):
• HTTP POST /api/match/init WITH Token+User-Id headers → 200 (browser & native).
• Socket.IO WebSocket upgrade WITH Token+User-Id headers, from a non-browser client (Bun, which can set WS handshake headers) → 101 Upgrade + engine.io open packet `0{"sid":"…",…}`. PROVES the gateway does forward WebSocket → HTTP byosnap; native was never broken.
• Socket.IO HTTP long-polling handshake (GET …/socket.io/?EIO=4&transport=polling) WITH headers → 200 + `0{"sid":"…","upgrades":["websocket"],…}` (works from a browser, because it's a plain HTTP request).
• Browser WebSocket upgrade with NO auth → rejected, close 1006.
• Browser WebSocket upgrade with token in query string (&token=… and &Token=&User-Id=) → rejected, close 1006.
• Browser WebSocket upgrade with token in Sec-WebSocket-Protocol (`["token.<session_token>"]`) → rejected, close 1006.

Conclusion: every browser-reachable auth mechanism for the WS upgrade is rejected by the gateway; only header-bearing (non-browser) WS upgrades, and plain HTTP requests, get through.

Fix options (both client-side; tracked separately): (A) add an Engine.IO v4 HTTP long-polling transport to validator_client.gd, used when OS.has_feature("web") — each poll/send is an HTTP request carrying the headers; NO server redeploy (proven through the live gateway). (B) add plain HTTP validate/complete endpoints to the validator and a request/response transport for web — needs a BYOSnap redeploy. Upstream: filed a Snapser request for a browser-compatible WS auth path (query-string token or Sec-WebSocket-Protocol) — see repo SNAPSER_BUG_REPORT_websocket_gateway_auth.md.

## Resolution
_None._

## References
_None._

## Child pages
_None._
