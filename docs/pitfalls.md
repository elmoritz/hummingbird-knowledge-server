# Pitfalls — Quick Reference

[← Testing & Deployment](testing-deployment.md) | [Home](index.md) | [Next: Clean Architecture →](clean-architecture.md)

---

## 18. All Pitfalls

| # | Pitfall | Severity |
|---|---------|---------|
| 1 | Using 1.x APIs in a 2.x project | Critical |
| 2 | Blocking the event loop with synchronous I/O or `Thread.sleep` | Critical |
| 3 | Consuming the request body twice | Critical |
| 4 | Not setting a max body size (unlimited upload attack surface) | Critical |
| 5 | Missing `SIGTERM` handler — Docker kills the process after 10s | Critical |
| 6 | Services not responding to graceful shutdown cancellation | Error |
| 7 | Shared mutable state without actor protection | Critical |
| 8 | Hardcoded secrets in source code | Critical |
| 9 | Using SHA/MD5 for password hashing instead of Bcrypt | Critical |
| 10 | Not parameterising SQL queries (SQL injection) | Critical |
| 11 | Constructing services inside route handlers (bypasses DI) | Error |
| 12 | Domain models returned directly as HTTP responses (leaks internal fields) | Error |
| 13 | `import Hummingbird` in a service layer file | Error |
| 14 | Raw database errors propagating to callers | Error |
| 15 | Global mutable state used as dependency storage | Critical |
| 16 | `JSONDecoder()` instantiated in a hot path | Warning |
| 17 | Too many database connections (exhausts `max_connections`) | Error |
| 18 | Not enabling strict concurrency checking in Package.swift | Error |
| 19 | Not implementing a `/health` endpoint | Error |
| 20 | Benchmarking debug builds | Warning |

For full details on each pitfall, see the relevant section in:
- [Introduction](introduction.md) — pitfall #1 (1.x → 2.x)
- [Core Concepts](core-concepts.md) — pitfalls #3, #4
- [Concurrency & Services](concurrency-services.md) — pitfalls #2, #5, #6, #7, #18
- [Integrations](integrations.md) — pitfalls #9, #10, #17
- [Testing & Deployment](testing-deployment.md) — pitfalls #19, #20
- [Clean Architecture](clean-architecture.md) — pitfalls #8, #11, #12, #13, #14, #15, #16

---

[← Testing & Deployment](testing-deployment.md) | [Home](index.md) | [Next: Clean Architecture →](clean-architecture.md)
