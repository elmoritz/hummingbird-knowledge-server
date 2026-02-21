# Introduction

[← Home](index.md) | [Next: Core Concepts →](core-concepts.md)

---

## 1. Why Swift for Servers

Swift is a credible production choice for server-side work as of 2025/2026. The practical reasons:

**Performance.** Compiled via LLVM, performance is competitive with Go and significantly ahead of Python, Ruby, or Node.js for CPU-bound work. Apple's internal Password Monitoring Service migrated a Java backend to Swift and reported a 40% performance improvement, 50% fewer Kubernetes nodes, and 85% less code.

**Safety.** Swift 6 strict concurrency checking catches data races at compile time — something no other mainstream server language does by default. Combined with value semantics, optionals, and typed errors, an entire class of runtime bugs simply don't compile.

**Code sharing.** For teams building both a Swift app and a backend, the domain model, business logic, validation rules, and API contracts can be shared across targets. No other backend language offers this with iOS/macOS clients.

**Private Cloud Compute.** Apple runs Swift at scale for their most security-sensitive infrastructure. This is the strongest possible signal that Swift on Linux is production-viable.

**The honest trade-offs:**
- Smaller community than Go, Java, or Node.js. Fewer Stack Overflow answers, fewer packages.
- Compile times are slower than Go. Cold Docker build times are a real cost.
- The ecosystem is younger — some packages are pre-1.0 and APIs move.
- Windows support is still experimental. Linux and macOS are the production targets.

---

## 2. Ecosystem & Dependency Stack

Understanding the layered stack is essential. When something breaks, knowing which layer is responsible prevents hours of misattribution.

```
swift-nio                   Async I/O runtime — event loops, channels, byte buffers
swift-nio-ssl               TLS via BoringSSL
swift-nio-http1             HTTP/1.1 codec
swift-nio-http2             HTTP/2 codec (optional)
swift-http-types            Shared types: HTTPRequest, HTTPResponse, HTTPFields
swift-service-lifecycle     Structured start/stop — graceful shutdown
swift-log                   Structured logging abstraction
swift-metrics               Metrics abstraction (Prometheus, StatsD backends)
hummingbird                 HTTP server framework built on top of all of the above
```

**Key SSWG-incubated packages for common concerns:**

| Concern | Package |
|---------|---------|
| PostgreSQL | `swift-server/postgres-nio` |
| MongoDB | `orlandos-uk/MongoKitten` |
| Redis | `swift-server/RediStack` |
| HTTP client | `swift-server/async-http-client` |
| AWS SDK | `soto-project/soto` |
| JWT | `vapor/jwt-kit` |
| OpenTelemetry | `swift-otel/swift-otel` |
| WebSockets | `hummingbird-project/hummingbird-websocket` |
| Jobs / queues | `hummingbird-project/hummingbird-jobs` |
| Auth middleware | `hummingbird-project/hummingbird-auth` |

Always check the SSWG package index at `swift.org/server/packages/` before adding a dependency. SSWG-incubated packages have stronger Linux compatibility guarantees than arbitrary Swift packages that were written for Apple platforms.

---

## 3. Hummingbird 2.x Overview

Hummingbird is a lightweight, flexible HTTP server framework built on SwiftNIO, maintained by Adam Fowler. It is the primary framework recommended by the Swift Server Working Group for new projects.

**Design philosophy:** Hummingbird deliberately minimises its core. The base library provides only routing, middleware, and request/response handling. Everything else — auth, jobs, WebSockets, database — is an optional add-on. This is the opposite of Vapor's batteries-included approach, and it has real benefits: smaller compile times, smaller binaries, no transitive dependencies you didn't ask for.

**Hummingbird vs Vapor** (senior-level comparison):

| Dimension | Hummingbird 2.x | Vapor 4.x |
|-----------|----------------|-----------|
| Concurrency model | Native async/await throughout | EventLoopFuture + async/await bridge |
| DI approach | RequestContext (typed, compile-time) | Application.Storage (runtime key-value) |
| Foundation dependency | Minimal | Heavy |
| Binary size | Small | Large |
| Compile times | Fast | Slow |
| Community size | Smaller | Larger |
| Ecosystem maturity | Growing | Established |
| Best fit | Greenfield, performance-sensitive, clean-arch | Teams with existing Vapor investment |

Note: Vapor 5 (no confirmed release date as of early 2026) will adopt Hummingbird's HTTP server core. The two ecosystems are converging.

---

## 4. The 1.x → 2.x Break — Most Important Pitfall

**Hummingbird 2.0 was a ground-up rewrite released in 2024. The API changed completely.**

Any tutorial, blog post, Stack Overflow answer, or GitHub Gist from before mid-2024 targets 1.x. That code will not compile against 2.x. This is the single most common source of confusion for new developers.

**Key API changes:**

| 1.x | 2.x |
|-----|-----|
| `HBApplication` | `ApplicationProtocol` + `buildApplication()` |
| `HBMiddleware` | `RouterMiddleware` |
| `HBHTTPError` | `HTTPError` |
| `EventLoopFuture<T>` everywhere | `async throws -> T` everywhere |
| `app.router.get(...)` | `router.get(...)` on a typed `Router(context:)` |
| `HBRequest` | `Request` (from swift-http-types) |
| Custom `HBResponse` | `Response` (from swift-http-types) |

**How to verify which version you're targeting:**

```bash
swift package show-dependencies | grep hummingbird
```

When reading any external Hummingbird content, look for these 2.x signals before trusting the code:
- `Router(context: MyContext.self)` — typed router, 2.x only
- `struct MyContext: RequestContext` — 2.x only
- `async throws ->` in route handlers — 2.x only
- `runService()` — 2.x only

---

[← Home](index.md) | [Next: Core Concepts →](core-concepts.md)
