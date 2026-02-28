// Sources/HummingbirdKnowledgeServer/KnowledgeBase/ArchitecturalViolations.swift
//
// The anti-tutorial rule catalogue.
// Each violation has a regex pattern matched against user-submitted source code.
// Critical violations block code generation entirely.

import Foundation

/// A rule that identifies an architectural anti-pattern in Hummingbird 2.x code.
struct ArchitecturalViolation: Sendable {
    let id: String
    let pattern: String         // Regex matched against source code
    let description: String
    let correctionId: String    // Knowledge base entry ID for the fix
    let severity: Severity

    enum Severity: Sendable {
        case warning    // Suboptimal but not incorrect
        case error      // Wrong — will cause problems
        case critical   // Blocks code generation entirely
    }
}

/// The complete catalogue of known Hummingbird 2.x architectural violations.
/// Loaded at startup; matched against every code snippet submitted to the server.
enum ArchitecturalViolations {

    static let all: [ArchitecturalViolation] = [

        // ── Critical: blocks code generation ──────────────────────────────────

        ArchitecturalViolation(
            id: "inline-db-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.query|pool\.|db\.)"#,
            description: "Database calls inside a route handler closure. "
                + "Route handlers must be pure dispatchers — all DB access belongs "
                + "in the repository layer, called via the service layer.",
            correctionId: "route-handler-dispatcher-only",
            severity: .critical
        ),

        ArchitecturalViolation(
            id: "service-construction-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*\w+Service\s*\("#,
            description: "Service constructed inline inside a route handler. "
                + "Services must be injected via AppRequestContext — never constructed "
                + "per-request inside a handler closure.",
            correctionId: "dependency-injection-via-context",
            severity: .critical
        ),

        // ── Error: wrong architecture ─────────────────────────────────────────

        ArchitecturalViolation(
            id: "hummingbird-import-in-service",
            pattern: #"^import\s+Hummingbird"#,
            description: "Hummingbird imported in a file under Services/ or Repositories/. "
                + "The service layer must be framework-agnostic. "
                + "Only controllers, middleware, and Application+build.swift may import Hummingbird.",
            correctionId: "service-layer-no-hummingbird",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "raw-error-thrown-from-handler",
            pattern: #"throw\s+(?!HTTPError|AppError)\w+Error"#,
            description: "A third-party or raw error is thrown directly from a route handler. "
                + "All errors must be wrapped in AppError before propagating — "
                + "this ensures consistent HTTP responses and prevents leaking internals.",
            correctionId: "typed-errors-app-error",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "domain-model-across-http-boundary",
            pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*(?!Response|some ResponseGenerator)\w+Model"#,
            description: "A domain model is returned directly from a route handler. "
                + "DTOs must be used at every HTTP boundary — domain models must never "
                + "cross the HTTP layer raw.",
            correctionId: "dtos-at-boundaries",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "domain-entity-across-http-boundary",
            pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*(?!Response|some ResponseGenerator)\w+Entity"#,
            description: "A domain entity is returned directly from a route handler. "
                + "DTOs must be used at every HTTP boundary — domain entities must never "
                + "cross the HTTP layer raw.",
            correctionId: "dtos-at-boundaries",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "domain-model-array-across-http-boundary",
            pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*\[\w+(Model|Entity)\]"#,
            description: "An array of domain models/entities is returned directly from a route handler. "
                + "DTOs must be used at every HTTP boundary — convert domain models to DTOs "
                + "before returning from route handlers.",
            correctionId: "dtos-at-boundaries",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "domain-model-in-request-decode",
            pattern: #"request\.decode\(as:\s*\w+(Model|Entity)\.self"#,
            description: "Domain model or entity used in request.decode(). "
                + "DTOs must be used at HTTP boundaries — decode to a DTO, "
                + "then convert to domain model in the service layer.",
            correctionId: "dtos-at-boundaries",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "business-logic-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(if\s+\w+\s*[<>=!]+|switch\s+\w+|for\s+\w+\s+in|\.calculate|\.compute|\.process(?!DTO))"#,
            description: "Business logic detected inside a route handler closure. "
                + "Route handlers must be thin dispatchers — all business rules, "
                + "calculations, and processing logic belongs in the service layer.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "validation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(guard\s+[^}]*(\.isEmpty|\.count|\.contains|!\.)|if\s+[^}]*(\.isEmpty|\.count|\.contains|!\.))"#,
            description: "Validation logic detected inside a route handler closure. "
                + "Input validation must be handled by DTO decoding conformance "
                + "or moved to the service layer — handlers should only dispatch.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "data-transformation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.map\s*\{|\.flatMap\s*\{|\.compactMap\s*\{|\.reduce\(|\.filter\s*\{)"#,
            description: "Data transformation detected inside a route handler closure. "
                + "Mapping, filtering, and data formatting belongs in the service layer "
                + "or DTO conversion — handlers should receive transformed data, not create it.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "missing-request-decode",
            pattern: #"router\.(post|put|patch).*\{(?!.*request\.decode\(|.*decode\(as:)[^}]{50,}\}"#,
            description: "POST/PUT/PATCH handler with no request.decode() call. "
                + "Handlers that accept request bodies must decode them into DTOs "
                + "for type safety and validation — never parse request data manually.",
            correctionId: "dtos-at-boundaries",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "unchecked-uri-parameters",
            pattern: #"request\.uri\.path(?!\s*(==|!=|\.starts|\.contains))|\blet\s+\w+\s*=\s*request\.uri\.path\b"#,
            description: "Direct access to request.uri.path without validation. "
                + "URI paths must be validated before use — either through route parameter "
                + "binding with type constraints or explicit validation in DTOs.",
            correctionId: "request-validation-via-dto",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "unchecked-query-parameters",
            pattern: #"request\.uri\.queryParameters(?!\s*\.isEmpty)|\blet\s+\w+\s*=\s*request\.uri\.queryParameters\[(?!.*guard|.*if let)"#,
            description: "Direct access to query parameters without validation. "
                + "Query parameters must be validated through DTO decoding — "
                + "never access queryParameters dictionary directly and pass raw values to services.",
            correctionId: "request-validation-via-dto",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "raw-parameter-in-service-call",
            pattern: #"service\.\w+\([^)]*request\.(uri|parameters|headers)\."#,
            description: "Raw request property passed directly to service layer method. "
                + "All request data must be validated and converted to DTOs before "
                + "passing to the service layer — services must not receive raw Request objects.",
            correctionId: "request-validation-via-dto",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "direct-env-access",
            pattern: #"(ProcessInfo\.processInfo\.environment\[|getenv\(|ProcessInfo\.environment)"#,
            description: "Direct environment variable access in application code. "
                + "All configuration must be loaded through a centralized Configuration struct "
                + "at startup — never access environment variables directly at runtime.",
            correctionId: "centralized-configuration",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "hardcoded-url",
            pattern: #"(let|var)\s+\w+\s*(:\s*String)?\s*=\s*"https?://[^"]+""#,
            description: "Hardcoded URL in source code. "
                + "All URLs, endpoints, and external service addresses must be "
                + "defined in configuration — never hardcoded as string literals.",
            correctionId: "centralized-configuration",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "hardcoded-credentials",
            pattern: #"(let|var)\s+\w*(password|secret|key|token|apiKey|apiSecret)\w*\s*=\s*"[^"]+"(?!")"#,
            description: "Hardcoded credential or secret in source code. "
                + "Secrets must NEVER be committed to code — use environment variables "
                + "loaded through secure configuration at runtime.",
            correctionId: "secure-configuration",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "swallowed-error",
            pattern: #"catch\s*\{[\s\n]*\}"#,
            description: "Empty catch block that swallows errors without handling. "
                + "Silently ignoring errors hides failures and makes debugging impossible — "
                + "always log errors, convert them to AppError, or handle them explicitly.",
            correctionId: "typed-errors-app-error",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "error-discarded-with-underscore",
            pattern: #"catch\s+(_|\w+)\s*\{(?!.*logger|.*log\.|.*throw|.*AppError)"#,
            description: "Error caught but not logged or re-thrown. "
                + "Catching an error without logging it or wrapping it in AppError "
                + "makes production debugging impossible — always preserve error context.",
            correctionId: "typed-errors-app-error",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "generic-error-message",
            pattern: #"throw\s+\w*Error\("[^"]{1,20}"\)(?!.*:)"#,
            description: "Error thrown with generic message and no context. "
                + "Error messages must include context about what failed and why — "
                + "add details like entity IDs, operation names, or input values that failed validation.",
            correctionId: "typed-errors-app-error",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "print-in-error-handler",
            pattern: #"catch[^}]*\{[^}]*(print\(|debugPrint\()"#,
            description: "print() or debugPrint() used in error handling instead of structured logging. "
                + "Print statements are not searchable, not structured, and disappear in production — "
                + "use Logger with proper log levels and context instead.",
            correctionId: "structured-logging",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "missing-error-wrapping",
            pattern: #"catch\s+let\s+(\w+)\s*\{[^}]*throw\s+\1\s*\}"#,
            description: "Third-party error re-thrown directly without wrapping in AppError. "
                + "Raw errors from libraries leak implementation details to clients — "
                + "wrap all external errors in AppError with context about the operation that failed.",
            correctionId: "typed-errors-app-error",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "sleep-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(sleep\(|Thread\.sleep|usleep\()"#,
            description: "Sleep call detected inside a route handler. "
                + "Blocking the thread pool with sleep() destroys concurrency performance — "
                + "use Task.sleep() or await-based delays instead of blocking sleep calls.",
            correctionId: "async-concurrency-patterns",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "blocking-io-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(FileHandle\(|FileManager\.default\.(contents|createFile|removeItem|moveItem|copyItem)\(|fopen\(|fread\(|fwrite\()"#,
            description: "Blocking file I/O operation in async context. "
                + "Synchronous file operations block the async thread pool — "
                + "use AsyncFileHandle, NIO's NonBlockingFileIO, or dispatch to a dedicated queue.",
            correctionId: "non-blocking-io",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "synchronous-network-call",
            pattern: #"(URLSession\.shared\.dataTask\(|NSURLConnection\.sendSynchronousRequest|URLSession\(configuration:.*\)\.dataTask\()(?!.*await)"#,
            description: "Synchronous or completion-handler-based network call. "
                + "Legacy URLSession.dataTask blocks threads and breaks structured concurrency — "
                + "use async/await URLSession.data(for:) instead.",
            correctionId: "async-concurrency-patterns",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "blocking-sleep-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(sleep\(|Thread\.sleep|usleep\()"#,
            description: "Blocking sleep call in async context. "
                + "sleep() and Thread.sleep() block the cooperative thread pool — "
                + "use Task.sleep(nanoseconds:) or Task.sleep(for:) to yield correctly.",
            correctionId: "async-concurrency-patterns",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "synchronous-database-call-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(\.execute\(\)|\.query\()[^}]*(?!await)"#,
            description: "Database call in async context without await. "
                + "Synchronous database operations block the thread pool — "
                + "all database calls must use async/await to preserve concurrency.",
            correctionId: "async-concurrency-patterns",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "global-mutable-state",
            pattern: #"^(public\s+|internal\s+|private\s+)?var\s+\w+\s*:\s*(?!@Sendable)[^\n]*=(?!\s*\{)"#,
            description: "Global mutable variable declared without actor protection or @MainActor isolation. "
                + "Global mutable state causes data races in concurrent code — "
                + "use actors, @MainActor, or make the value immutable (let) instead.",
            correctionId: "actor-for-shared-state",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "missing-sendable-conformance",
            pattern: #"(struct|class|enum)\s+\w+(?!.*:\s*.*Sendable)[^{]*(:\s*[^{]*)?(?=\s*\{)"#,
            description: "Type declaration without Sendable conformance in concurrent context. "
                + "Types used across concurrency boundaries must conform to Sendable — "
                + "add `: Sendable` to structs/enums/actors, or use `final class` with all immutable properties.",
            correctionId: "sendable-types",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "task-detached-without-isolation",
            pattern: #"Task\.detached\s*\{(?!.*@MainActor|.*actor)"#,
            description: "Task.detached called without explicit isolation annotation. "
                + "Detached tasks inherit no isolation and can cause data races — "
                + "use Task { } for structured concurrency or explicitly annotate isolation with @MainActor.",
            correctionId: "structured-concurrency",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "nonisolated-unsafe-usage",
            pattern: #"nonisolated\s*\(unsafe\)"#,
            description: "nonisolated(unsafe) used to bypass Swift 6 concurrency checks. "
                + "This attribute disables safety guarantees and can cause data races — "
                + "use proper actor isolation or Sendable conformance instead of unsafe escapes.",
            correctionId: "actor-for-shared-state",
            severity: .error
        ),

        // ── Warning: suboptimal patterns ──────────────────────────────────────

        ArchitecturalViolation(
            id: "shared-mutable-state-without-actor",
            pattern: #"var\s+\w+\s*:\s*\[.*\]\s*=\s*\[.*\]"#,
            description: "Mutable collection stored as a var at module or class scope "
                + "without actor protection. In Swift 6 strict concurrency, shared "
                + "mutable state requires an actor or explicit synchronisation.",
            correctionId: "actor-for-shared-state",
            severity: .warning
        ),

        ArchitecturalViolation(
            id: "nonisolated-context-access",
            pattern: #"nonisolated.*context\.\w+"#,
            description: "AppRequestContext properties accessed from a nonisolated context. "
                + "Context is value-typed (struct) and Sendable — pass it explicitly "
                + "rather than capturing it across isolation boundaries.",
            correctionId: "request-context-di",
            severity: .warning
        ),

        ArchitecturalViolation(
            id: "magic-numbers",
            pattern: #"(timeout|limit|maxConnections|port|bufferSize|retryCount)\s*[=:]\s*\d{2,}"#,
            description: "Magic number used for configuration value. "
                + "Numeric configuration constants (timeouts, limits, ports, etc.) "
                + "should be defined as named constants or loaded from configuration, "
                + "not embedded as raw literals.",
            correctionId: "centralized-configuration",
            severity: .warning
        ),
    ]
}
