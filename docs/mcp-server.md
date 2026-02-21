# MCP Server

[← Clean Architecture](clean-architecture.md) | [Home](index.md) | [Next: References →](references.md)

---

## 25. MCP Server Architecture

### What MCP Is

The Model Context Protocol (MCP) is an open standard that defines how AI assistants communicate with external knowledge sources and tools. An MCP server exposes three primitive types:

- **Tools** — callable functions (e.g., `check_architecture`, `explain_error`)
- **Resources** — readable documents (e.g., pitfall catalogue, migration guide)
- **Prompts** — conversation templates (e.g., architecture review session)

Communication uses JSON-RPC 2.0.

### Transport: Streamable HTTP (MCP spec 2025-06-18)

The current MCP spec defines a single `/mcp` endpoint that handles both:
- `GET /mcp` → opens an SSE stream for server-to-client messages
- `POST /mcp` → client-to-server JSON-RPC messages

> **Important:** The older `/sse` + `/messages` split from spec 2024-11-05 is superseded. Use the single-endpoint Streamable HTTP transport.

### The Swift SDK Transport Gap

The official MCP Swift SDK (`modelcontextprotocol/swift-sdk`) provides `HTTPClientTransport` for *clients*, not servers. There is no built-in HTTP server transport. You must implement a custom `Transport` actor that bridges Hummingbird's request handling into the MCP SDK's message stream protocol.

This is exactly what `HummingbirdSSETransport` in the `hummingbird-knowledge-server` does.

### Tool Design Principles

Every tool that generates code must return:

```swift
struct GeneratedCodeResponse: Codable {
    let code: String
    let filePath: String                  // e.g. "Sources/App/Services/UserService.swift"
    let layer: ArchitecturalLayer         // service, repository, controller, etc.
    let dependencies: [FileDependency]    // other files required for this to compile
    let demonstratedPatterns: [String]    // patterns shown
    let detectedViolations: [String]      // violations found in user-submitted code
}
```

Structuring output this way makes it impossible to return a bare code snippet — the layer context is always present.

### The Anti-Tutorial System Prompt

The single most powerful mechanism for keeping the MCP server architecturally opinionated is its system prompt. Key rules to encode:

```
1. Route handlers are dispatchers only — no business logic, no DB calls, no service construction.
2. Business logic lives in the service layer — no Hummingbird imports.
3. Dependencies are injected via AppRequestContext — never constructed inline.
4. All errors are typed AppError values — raw third-party errors are always wrapped.
5. DTOs at every boundary — domain models never cross the HTTP layer raw.
6. When asked for a "quick" or "simple" solution, produce the correct architecture
   anyway and explain why brevity without structure creates long-term cost.
7. Always show: the protocol, the implementation, and the injection point.
   Never show just usage without showing where the dependency comes from.
```

### Architectural Violation Detection

The server maintains a catalogue of known violations matched against user-submitted code:

```swift
struct ArchitecturalViolation: Sendable {
    let id: String
    let pattern: String        // regex matched against source code
    let description: String
    let correctionId: String   // knowledge base entry ID for the fix
    let severity: Severity     // warning | error | critical
}

// Examples:
// id: "inline-db-in-handler"
// pattern: router\.{method} closure directly containing .query or pool.
// severity: .critical

// id: "hummingbird-import-in-service"
// pattern: ^import Hummingbird in a Service/ file
// severity: .error
```

Critical violations block code generation entirely. The server regenerates rather than returning violating code.

---

## 26. Auto-Update & Self-Healing

### Three-Layer Knowledge Model

| Layer | Updated | Mechanism |
|-------|---------|-----------|
| Embedded | At release | Compiled into binary — core pitfalls, arch rules |
| Cached | Hourly | `KnowledgeUpdateService` — GitHub Releases, SSWG index |
| Live | On demand | Tool fetches when cached data is stale or missing |

### Sources to Monitor

| Source | URL | What to fetch |
|--------|-----|--------------|
| GitHub Releases API | `api.github.com/repos/hummingbird-project/hummingbird/releases/latest` | Version, changelog |
| SSWG Package Index | `swift.org/server/packages/` | Incubation statuses |
| Swift Forums | `forums.swift.org/c/server` | Breaking change announcements |
| GitHub Discussions | `hummingbird-project/hummingbird/discussions` | Community-reported issues |

### Knowledge Entry Schema

```swift
struct KnowledgeEntry: Codable, Sendable {
    let id: String
    let title: String
    let content: String
    let layer: ArchitecturalLayer?
    let patternIds: [String]
    let violationIds: [String]
    let hummingbirdVersionRange: String   // semver, e.g. ">=2.0.0"
    let swiftVersionRange: String         // e.g. ">=6.0"
    let isTutorialPattern: Bool           // true = this is an anti-pattern example
    let correctionId: String?             // required when isTutorialPattern == true
    let confidence: Double                // 0.0 to 1.0
    let source: String
    let lastVerifiedAt: Date?
}
```

Anti-patterns exist in the knowledge base as `isTutorialPattern: true` entries. When the server detects user code matching one, it recognises it as a violation and redirects to the `correctionId` entry.

### Self-Healing via `report_issue`

```swift
Tool(
    name: "report_issue",
    description: "Report an incorrect or outdated answer from this MCP server",
    inputSchema: .object(properties: [
        "tool_name":          .string,
        "query":              .string,
        "problem":            .string,
        "hummingbird_version": .string,
        "swift_version":      .string,
    ])
)
```

Reports are logged and prioritised in the next `KnowledgeUpdateService` cycle. This is the primary mechanism by which the knowledge base improves over time.

---

## 27. hummingbird-knowledge-server — Implementation

### Repository Structure

```
Sources/HummingbirdKnowledgeServer/
├── main.swift                          Bootstrap — logging, config, runService()
├── Application+build.swift             Composition root — only file with concrete types
├── Configuration/
│   └── AppConfiguration.swift          Environment-driven config, fails fast
├── Context/
│   ├── AppRequestContext.swift          DI container carried per-request
│   └── AppDependencies.swift            Immutable dependency graph
├── Transport/
│   └── HummingbirdSSETransport.swift    Custom MCP ↔ Hummingbird SSE bridge
├── Controllers/
│   ├── Controller.swift                 Protocol all controllers conform to
│   └── MCPController.swift             GET /mcp (SSE) + POST /mcp (messages)
├── MCPServer/
│   ├── Tools/
│   │   ├── ToolRegistration.swift
│   │   ├── CheckArchitectureTool.swift  Fully implemented
│   │   └── [9 more tools]              Stubs — implement following CheckArchitecture pattern
│   ├── Resources/
│   │   └── ResourceRegistration.swift
│   └── Prompts/
│       └── PromptRegistration.swift
├── KnowledgeBase/
│   ├── KnowledgeStore.swift            Actor — thread-safe, loaded at startup
│   ├── ArchitecturalViolations.swift   The anti-tutorial rule catalogue
│   └── knowledge.json                  10 seed entries
├── AutoUpdate/
│   └── KnowledgeUpdateService.swift    Background Service — GitHub + SSWG polling
├── Errors/
│   └── AppError.swift
└── Middleware/
    ├── DependencyInjectionMiddleware.swift
    ├── AuthMiddleware.swift
    ├── RateLimitMiddleware.swift
    └── RequestLoggingMiddleware.swift
```

### Tools — Complete List

| Tool | Status | Purpose |
|------|--------|---------|
| `check_architecture` | Implemented | Detect violations in submitted code |
| `explain_error` | Stub | Diagnose error messages and stack traces |
| `explain_pattern` | Stub | Full pattern explanation with protocol + impl + injection |
| `generate_code` | Stub | Produce idiomatic 2.x code with layer metadata |
| `get_best_practice` | Stub | Best practice for a given topic |
| `list_pitfalls` | Stub | Ranked pitfall list, filterable by category |
| `diagnose_startup_failure` | Stub | Step-by-step startup error diagnosis |
| `check_version_compatibility` | Stub | 1.x vs 2.x compatibility for a code snippet |
| `get_package_recommendation` | Stub | SSWG-vetted package for a given need |
| `report_issue` | Stub | Community feedback for self-healing |

All stubs follow the same pattern as `CheckArchitectureTool` — `struct MyTool { let store: KnowledgeStore; func register(on server: Server) }`.

### Key Architectural Decisions Made

**Why Swift?** The codebase is part of the teaching material. Developers clone it, read it, and see the same patterns the MCP server recommends applied to a real production application. Dogfooding is genuine value, not rationalisation.

**Why custom `HummingbirdSSETransport`?** The MCP Swift SDK only provides client-side HTTP transport. The server-side transport must be implemented manually by bridging Hummingbird's response body writers into the MCP SDK's `AsyncThrowingStream<Data, Error>` message protocol.

**Why `isTutorialPattern` in the knowledge base?** Tutorial patterns need to exist in the knowledge base as named anti-patterns so the server can recognise them in user code and redirect to the correct approach — not just ignore them.

**Why is `AppDependencies.placeholder` a crash?** If `DependencyInjectionMiddleware` is misconfigured or removed, the crash happens at the first request with a clear message. Silent failures that produce incorrect results are worse than loud failures that identify the cause.

---

## 28. Deployment Model C — Local + Hosted

The server supports both models simultaneously, detected automatically from environment variables.

### Mode Detection

```
MCP_AUTH_TOKEN not set → Local mode
  - Binds to 127.0.0.1 by default
  - No authentication
  - Rate limiting disabled
  - Connect at http://localhost:8080/mcp

MCP_AUTH_TOKEN set → Hosted mode
  - Binds to 0.0.0.0 by default
  - All /mcp requests require: Authorization: Bearer <token>
  - Rate limiting active (default: 60 req/min)
  - Connect at https://your-domain.com/mcp
```

This is controlled entirely by `AppConfiguration` — no compile-time flags, no separate builds, no conditional compilation.

### Middleware Stack (Hosted Mode)

```
DependencyInjectionMiddleware  ← always first
RequestLoggingMiddleware       ← always present
AuthMiddleware                 ← only when MCP_AUTH_TOKEN is set
RateLimitMiddleware            ← only when MCP_AUTH_TOKEN is set
───────────────────────────────
GET  /health    ← always unauthenticated (load balancers, Docker HEALTHCHECK)
GET  /ready     ← always unauthenticated
GET  /mcp       ← opens SSE stream
POST /mcp       ← receives JSON-RPC messages
```

### Rate Limiter Design Notes

The current `RateLimitMiddleware` uses an in-memory sliding window actor. This works for single-instance deployments. For multiple container instances, replace the in-memory store with a Redis-backed counter (e.g. `RediStack`) so limits are shared across pods.

The middleware reads `X-Forwarded-For` preferentially over direct peer address — required when running behind a reverse proxy or load balancer, which is the normal hosted deployment topology.

### Claude Desktop Configuration

**Local:**
```json
{
  "mcpServers": {
    "hummingbird-knowledge-local": {
      "url": "http://localhost:8080/mcp",
      "transport": "sse"
    }
  }
}
```

**Hosted:**
```json
{
  "mcpServers": {
    "hummingbird-knowledge": {
      "url": "https://mcp.yourdomain.com/mcp",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer your_token_here"
      }
    }
  }
}
```

Both can be present simultaneously — they are independent servers.

### IDE Integrations

**Cursor:** Settings → Features → Model Context Protocol → Add server, type SSE, enter URL. Add `Authorization` header for hosted.

**VS Code (Continue extension):** `.continue/config.json` → `mcpServers` array with `transport: "sse"` and `url`.

**VS Code (Copilot Chat):** `.vscode/mcp.json` → `servers` object with `type: "sse"` and `url`.

**Zed:** `settings.json` → `context_servers` with `transport: "sse"` and `url`.

---

[← Clean Architecture](clean-architecture.md) | [Home](index.md) | [Next: References →](references.md)
