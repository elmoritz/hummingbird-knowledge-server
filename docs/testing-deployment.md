# Testing & Deployment

[← Integrations](integrations.md) | [Home](index.md) | [Next: Pitfalls Reference →](pitfalls.md)

---

## 15. Testing

### HummingbirdTesting

```swift
import HummingbirdTesting
import XCTest

final class UserRouteTests: XCTestCase {
    func testCreateUser() async throws {
        let app = buildTestApp()   // same function as production, with fakes injected

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/users",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"name":"Alice","email":"alice@example.com"}"#)
            )
            XCTAssertEqual(response.status, .created)
        }
    }
}
```

### Testing Modes

| Mode | What it tests | When to use |
|------|--------------|------------|
| `.router` | Routing, middleware, handlers (no network) | All unit/integration tests |
| `.live` | Real TCP stack, TLS, HTTP/2 | TLS config, WebSocket upgrades |

Use `.router` for 95%+ of tests. It is orders of magnitude faster than `.live` and doesn't consume system ports.

### Test Doubles via Fake Repositories

```swift
func buildTestApp() throws -> some ApplicationProtocol {
    let fakeUserRepo = FakeUserRepository()
    await fakeUserRepo.seed([User(id: UUID(), name: "Alice", email: "alice@example.com")])

    let dependencies = AppDependencies(
        userService: UserService(repository: fakeUserRepo),
        emailService: FakeEmailService()
    )

    let router = Router(context: AppRequestContext.self)
    router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
    UserController().registerRoutes(on: router.group("/users"))

    return Application(router: router)
}
```

The fake repository is an actor that satisfies the `UserRepositoryProtocol` in memory. No database. No network. Tests run in milliseconds.

---

## 16. Deployment

### Docker (Multi-Stage Build)

```dockerfile
# Stage 1: Build
FROM swift:6.0-jammy AS builder
WORKDIR /app
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources ./Sources
RUN swift build --configuration release --static-swift-stdlib

# Stage 2: Runtime (no Swift toolchain needed)
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y libcurl4 libxml2 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --system --create-home appuser
USER appuser
COPY --from=builder /app/.build/release/MyServer /usr/local/bin/server
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -f http://localhost:8080/health || exit 1
ENTRYPOINT ["/usr/local/bin/server"]
```

> **Pitfall:** `--static-swift-stdlib` embeds the Swift runtime into the binary. Without it, your runtime image must use `swift:slim` (much larger). Always use static linking for production containers.

### Health Checks

```swift
// Always implement these — required by load balancers, Docker, Kubernetes
router.get("/health") { _, _ in ["status": "ok"] }

router.get("/ready") { _, context in
    try await context.dependencies.db.ping()
    return ["status": "ok"]
}
```

### Platform Notes

- **Linux (Ubuntu 22.04, Amazon Linux 2023):** Primary production target. All SSWG packages are tested here.
- **macOS:** Development only. GCD vs NIO threading differences exist in edge cases.
- **AWS Lambda:** Use `swift-aws-lambda-runtime`. Hummingbird has an official Lambda transport adapter.
- **Windows:** Experimental. Not recommended for production.

---

## 17. Performance

- **Always benchmark release builds.** Debug builds are 10–100× slower due to no optimisation and extra safety checks. Never benchmark a debug build.
- **Thread pool defaults are usually correct.** One thread per CPU core is right for I/O-bound workloads. Don't increase without profiling data.
- **Offload TLS termination.** Handle TLS at the reverse proxy (nginx, Caddy, AWS ALB) rather than in your Swift process. Reduces CPU load and simplifies certificate management.
- **HTTP keep-alive is on by default.** Leave it enabled — it eliminates handshake overhead for clients making multiple requests.
- **Don't instantiate `JSONDecoder()` in hot paths.** Use a shared static instance or `request.decode(as:context:)`.

---

[← Integrations](integrations.md) | [Home](index.md) | [Next: Pitfalls Reference →](pitfalls.md)
