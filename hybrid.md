# Hybrid WebView Authentication Design

## Core Principle: Native Owns Auth

In our hybrid architecture, the **native app is the single owner of authentication**. The WebView is a rendering surface — it never independently manages tokens, refreshes sessions, or stores credentials.

```
Native App (Swift)                    Web Frontend (React)
┌──────────────────────┐              ┌──────────────────────┐
│ AuthManager          │  injects     │ fetchWithRefresh()   │
│ ├── Keychain tokens  │ ──token───►  │ ├── reads token      │
│ ├── refreshToken()   │              │ ├── adds Auth header │
│ └── single source    │  ◄──401───   │ └── asks native to   │
│     of truth         │   refresh    │     refresh on 401   │
└──────────────────────┘              └──────────────────────┘
```

**Why native owns auth:**
- **Single source of truth** — tokens live in Keychain, not in cookies or JS variables
- **No dual-writer races** — only native refreshes tokens; web never calls `/api/system/oauth/refresh` directly
- **Cross-view consistency** — all WebPage instances read from the same AuthManager
- **Survives WebView crashes** — native re-injects token after process termination
- **Works offline** — native can check token validity without network

## How Token Injection Works

Native injects the access token into the WebView's JS context **before any page scripts run**, using `WKUserScript` at `documentStart`. The web frontend then uses this token for all API requests.

### Injection: WKUserScript at documentStart

```swift
// Native: registered before WebPage.load()
let script = """
    window.isNativeApp = true;
    window.__nativeAccessToken = '<jwt>';
    window.__nativeRecheckAuth = function() { ... };
    // bridge polyfill ...
"""
WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
```

WebKit guarantees `atDocumentStart` runs before ANY `<script>` tags. This is critical — React must see the token when it mounts, not after.

### Delivery: How the token reaches API requests

| Request type | Mechanism | Why |
|---|---|---|
| `fetch()` | `Authorization: Bearer <token>` header | JS can set headers on fetch; reliable, explicit |
| `WebSocket` | `?access_token=<token>` query parameter | WebSocket API cannot set custom headers (web standard limitation, not WebKit-specific) |
| Native API calls | `Authorization: Bearer <token>` header | `APIClient.swift` reads from AuthManager directly |

### Refresh: What happens when a token expires

```
1. fetchWithRefresh() gets 401
2. Calls refreshViaNativeBridge()
   → fetch('nativebridge://message', { action: 'requestTokenRefresh' })
3. Native: AuthManager.refreshAccessToken()
   → POST /api/system/oauth/refresh (refresh_token from Keychain)
   → stores new tokens in Keychain
4. Native responds: { success: true, accessToken: '<new_jwt>' }
5. Web: window.__nativeAccessToken = '<new_jwt>'
6. Retry original request with new Bearer header
```

### Background update: Proactive token push

```
1. Native detects token expiring (foreground resume, .authTokensDidChange)
2. Updates WKUserScript (for future page loads)
3. Calls callJavaScript("window.__nativeAccessToken = '...'") (for current page)
4. Subsequent fetches use the fresh token automatically
```

## Backend Auth Middleware

The Go backend (`api/middleware.go`) accepts auth credentials from three sources, checked in order:

| Priority | Source | Used by |
|---|---|---|
| 1 | `Authorization: Bearer <token>` header | `fetchWithRefresh` (native + desktop) |
| 2 | `access_token` query parameter | WebSocket connections (cannot set headers) |
| 3 | `access_token` cookie | Desktop browser (traditional web auth) |

All three paths validate the JWT identically.

## Why Not Cookies? Industry Context

### The problem

WebKit runs web content in a **separate process** from the app. This creates two independent cookie stores that don't reliably sync:

| Cookie store | Process | Used by |
|---|---|---|
| `HTTPCookieStorage.shared` | App process (Foundation) | `URLSession`, native HTTP calls |
| `WKHTTPCookieStore` | WebKit process | `fetch()`, `XMLHttpRequest`, page navigation |

iOS "automatically" syncs them, but with **seconds of delay**, and the sync is **unreliable** — cookies randomly go missing after backgrounding, memory pressure, or ITP enforcement.

### Evidence (well-documented, not just our observation)

- [WebKit Bug #200857](https://bugs.webkit.org/show_bug.cgi?id=200857) — cookies missing in cross-origin requests (iOS 13+)
- [WebKit Bug #213510](https://bugs.webkit.org/show_bug.cgi?id=213510) — ITP breaks cookies for hybrid apps (iOS 14+)
- [Apple Forums: randomly missing cookies](https://developer.apple.com/forums/thread/782064) — small % of requests lose cookies, especially after backgrounding
- [Apple Forums: cookies lost in background](https://developer.apple.com/forums/thread/745912) — iOS cleans up session cookies during memory pressure
- [Apple Forums: sync issues since iOS 11.3](https://developer.apple.com/forums/thread/99674) — HTTPCookieStorage ↔ WKHTTPCookieStore sync unreliable
- [Thinktecture: ITP in WKWebView](https://www.thinktecture.com/en/ios/wkwebview-itp-ios-14/) — detailed analysis of ITP impact
- [Axel Springer: native/WebView session sync](https://medium.com/axel-springer-tech/synchronization-of-native-and-webview-sessions-with-ios-9fe2199b44c9) — documents complexity and race conditions of cookie-based approach

This is a **structural consequence of WebKit's multi-process architecture** (security/stability design), not a bug that will be fixed.

### Industry approaches compared

| Approach | Used by | How it works | Limitation |
|---|---|---|---|
| **Cookie sync** | Axel Springer, many Cordova apps | Native writes cookies to `WKHTTPCookieStore`, WebView reads them | Unreliable sync, race conditions, ITP interference, random cookie loss after backgrounding |
| **Hidden WebView bootstrap** | Basecamp 3, HEY (Turbo iOS) | Native loads hidden WebView to a cookie-setting endpoint, then shows real WebView | Extra network round-trip latency, still relies on cookies staying alive |
| **Token injection + Auth header** | **Us**, React Native WebView apps | Native injects token via JS, web uses `Authorization` header | Requires frontend wrapper (`fetchWithRefresh`); WebSocket needs query param fallback |

We chose **token injection** because it **bypasses the cookie problem entirely** rather than working around it.

### WebSocket: why query parameter?

The browser `WebSocket` API (`new WebSocket(url)`) cannot set custom HTTP headers on the upgrade request. This is a **web platform limitation** (same in Chrome, Firefox, Safari — not WebKit-specific).

Standard workarounds ([Ably guide](https://ably.com/blog/websocket-authentication), [Python websockets docs](https://websockets.readthedocs.io/en/stable/topics/authentication.html)):

| Method | Tradeoff |
|---|---|
| **Query parameter** (what we use) | Simple; token may appear in server access logs (acceptable — we control the server) |
| `Sec-WebSocket-Protocol` header hack | Token smuggled in protocol header; works but misuses the field |
| First-message auth | Connect unauthenticated, send token as first message; requires server protocol change |

## If Cookies Become Reliable

If Apple fixes cookie delivery in a future iOS release, the **only change needed** is:

1. **Remove** the `isNativeApp` check in `fetchWithRefresh` (stop adding Authorization header)
2. **Remove** the `?access_token=` query parameter from WebSocket URL
3. **Keep** `WKUserScript` injection (still useful for bridge polyfill, feature flags, `isNativeApp` flag)
4. **Keep** native auth ownership (still the right design regardless of cookies)

The native-owns-auth architecture is **not a workaround for cookies** — it's the right design for a hybrid app. The cookie issue only affects how tokens are delivered to the backend (header vs cookie). Everything else stays the same.

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│  Native App (Swift)                             │
│                                                 │
│  AuthManager (singleton)                        │
│  ├── accessToken  (Keychain)                    │
│  ├── refreshToken (Keychain)                    │
│  └── refreshAccessToken() → POST /api/system/oauth/refresh
│                                                 │
│  TabWebViewModel                                │
│  ├── creates WebPage(configuration)             │
│  ├── injects WKUserScript at documentStart      │
│  │   → sets window.isNativeApp = true           │
│  │   → sets window.__nativeAccessToken = '...'  │
│  │   → sets window.__nativeRecheckAuth()        │
│  │   → sets window.__featureFlags = { ... }     │
│  │   → polyfills window.webkit.messageHandlers  │
│  └── updates __nativeAccessToken on refresh     │
│                                                 │
│  NativeBridgeHandler (URLSchemeHandler)          │
│  └── handles 'nativebridge://' requests         │
│      └── requestTokenRefresh → returns new token│
└────────────────────┬────────────────────────────┘
                     │ WebPage loads SPA
                     ▼
┌─────────────────────────────────────────────────┐
│  Web Frontend (React)                           │
│                                                 │
│  fetchWithRefresh()                             │
│  ├── if window.isNativeApp && __nativeAccessToken│
│  │   → adds Authorization: Bearer header        │
│  ├── on 401 → refreshAccessToken()             │
│  │   ├── native: fetch('nativebridge://...')    │
│  │   │   → receives { success, accessToken }    │
│  │   │   → updates window.__nativeAccessToken   │
│  │   └── web: POST /api/system/oauth/refresh (cookie)  │
│  └── retries with new token                     │
│                                                 │
│  useSessionWebSocket()                          │
│  ├── if window.isNativeApp && __nativeAccessToken│
│  │   → appends ?access_token= to WebSocket URL  │
│  └── desktop: cookies sent automatically        │
│                                                 │
│  AuthProvider                                   │
│  ├── checkAuth() → api.get('/api/system/settings') │
│  └── listens for 'native-recheck-auth' event    │
└─────────────────────────────────────────────────┘
```

## References

- WWDC25: [Meet WebKit for SwiftUI](https://developer.apple.com/videos/play/wwdc2025/231/)
- Apple: [WebPage.Configuration docs](https://developer.apple.com/documentation/webkit/webpage/configuration)
- Apple: [WKHTTPCookieStore docs](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
- Turbo iOS: [Authentication docs](https://github.com/hotwired/turbo-ios/blob/main/Docs/Authentication.md)
- [Masilotti: Turbo iOS Native Authentication](https://masilotti.com/turbo-ios/native-authentication/)
- [DEV.to: Authentication in Hybrid Mobile Apps](https://dev.to/itamartati/understanding-authentication-in-hybrid-mobile-apps-cookies-webviews-and-common-pitfalls-3m8)
