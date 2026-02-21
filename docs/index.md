# Hummingbird & Server-Side Swift — Knowledge Base

> **Scope:** Everything accumulated across this project — Hummingbird 2.x internals, clean architecture patterns, MCP server design, deployment strategy, and the `hummingbird-knowledge-server` implementation decisions. Written for engineers who want production-grade output, not tutorial code.

---

## Contents

| # | Topic | What's covered |
|---|-------|----------------|
| 1 | [Introduction](introduction.md) | Why Swift for servers, the dependency stack, Hummingbird overview, and the critical 1.x → 2.x migration break |
| 2 | [Core Concepts](core-concepts.md) | Application setup & entry point, routing, request/response handling, middleware |
| 3 | [Concurrency & Services](concurrency-services.md) | Swift Structured Concurrency pitfalls, actor safety, task cancellation, service lifecycle |
| 4 | [Integrations](integrations.md) | Database (PostgresNIO), authentication & JWT, WebSockets, background jobs |
| 5 | [Testing & Deployment](testing-deployment.md) | HummingbirdTesting modes, fake repositories, Docker multi-stage builds, performance tips |
| 6 | [Pitfalls Reference](pitfalls.md) | All 20 pitfalls ranked by severity — quick lookup table |
| 7 | [Clean Architecture](clean-architecture.md) | Layer model, dependency injection via RequestContext, the controller pattern, service layer, repository pattern, error handling |
| 8 | [MCP Server](mcp-server.md) | MCP protocol, transport implementation, tool design, auto-update & self-healing, deployment modes |
| 9 | [References](references.md) | Key links — GitHub repos, docs, specs, forums |

---

*Last updated: February 2026*
*Covers: Hummingbird 2.x · Swift 6.0 · MCP Spec 2025-06-18 · hummingbird-knowledge-server v0.1.0*
