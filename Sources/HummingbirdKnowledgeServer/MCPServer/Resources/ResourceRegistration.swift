// Sources/HummingbirdKnowledgeServer/MCPServer/Resources/ResourceRegistration.swift
//
// Exposes knowledge base content as readable MCP resources.
// Resources are documents that AI clients can read directly — unlike tools,
// they do not require parameters to be invoked.

import MCP

/// Registers all MCP resources on the server.
///
/// Resources expose static or semi-static content from the knowledge base.
/// They complement tools: tools answer questions interactively; resources
/// provide documents that can be read in full.
func registerResources(on server: Server, knowledgeStore: KnowledgeStore) async {
    await server.withMethodHandler(ListResources.self) { _ in
        ListResources.Result(resources: [
            Resource(
                name: "Pitfall Catalogue",
                uri: "hummingbird://pitfalls",
                description: "Complete ranked catalogue of known Hummingbird 2.x architectural pitfalls and anti-patterns.",
                mimeType: "text/plain"
            ),
            Resource(
                name: "Architecture Reference",
                uri: "hummingbird://architecture",
                description: "Clean architecture reference for Hummingbird 2.x: layers, responsibilities, and injection points.",
                mimeType: "text/plain"
            ),
            Resource(
                name: "Violation Catalogue",
                uri: "hummingbird://violations",
                description: "The compiled architectural violation rule set used by check_architecture.",
                mimeType: "text/plain"
            ),
        ])
    }

    await server.withMethodHandler(ReadResource.self) { params in
        switch params.uri {

        case "hummingbird://pitfalls":
            let content = await knowledgeStore.pitfallCatalogueText()
            return ReadResource.Result(contents: [
                .text(content, uri: params.uri, mimeType: "text/plain"),
            ])

        case "hummingbird://architecture":
            return ReadResource.Result(contents: [
                .text(architectureReferenceContent, uri: params.uri, mimeType: "text/plain"),
            ])

        case "hummingbird://violations":
            let violationText = ArchitecturalViolations.all.map { v in
                let severity: String
                switch v.severity {
                case .critical: severity = "CRITICAL"
                case .error:    severity = "ERROR"
                case .warning:  severity = "WARNING"
                }
                return "[\(severity)] \(v.id)\n\(v.description)\nCorrection: \(v.correctionId)"
            }.joined(separator: "\n\n---\n\n")

            return ReadResource.Result(contents: [
                .text(violationText, uri: params.uri, mimeType: "text/plain"),
            ])

        default:
            throw AppError.resourceNotFound(uri: params.uri)
        }
    }
}

// MARK: - Static content

private let architectureReferenceContent = """
# Hummingbird 2.x Clean Architecture Reference

## Layers and Responsibilities

### Controller Layer
- **Files:** `Sources/App/Controllers/*.swift`
- **Allowed imports:** `Hummingbird`, `Foundation`
- **Responsibility:** Decode HTTP requests, dispatch to services, encode responses
- **Forbidden:** Business logic, database calls, service construction

### Service Layer
- **Files:** `Sources/App/Services/*.swift`
- **Allowed imports:** `Foundation`, domain protocols — NOT Hummingbird
- **Responsibility:** Business logic, validation, orchestration
- **Forbidden:** HTTP types, Hummingbird imports, direct database access

### Repository Layer
- **Files:** `Sources/App/Repositories/*.swift`
- **Allowed imports:** Database driver, Foundation — NOT Hummingbird
- **Responsibility:** Data persistence, query construction
- **Forbidden:** Business logic, HTTP types

### Model Layer
- **Files:** `Sources/App/Models/*.swift`
- **Responsibility:** Domain entities — plain Swift structs and classes
- **Forbidden:** Framework imports, HTTP types, persistence logic

### Middleware Layer
- **Files:** `Sources/App/Middleware/*.swift`
- **Allowed imports:** `Hummingbird`
- **Responsibility:** Cross-cutting concerns: auth, rate limiting, logging
- **Pattern:** Conform to `RouterMiddleware` with `typealias Context = AppRequestContext`

## Dependency Injection

All dependencies flow through `AppRequestContext.dependencies`:

1. `AppDependencies` is constructed once in `Application+build.swift`
2. `DependencyInjectionMiddleware` copies it into every request context
3. Handlers read `context.dependencies.myService`
4. Nothing constructs services inline — ever

## Error Handling

- Service and repository layers throw `AppError`
- Controllers catch `AppError` and throw `HTTPError` with appropriate status codes
- Third-party errors are ALWAYS wrapped before propagating

## Concurrency Rules

- Shared mutable state lives in actors
- Route handler closures are `@Sendable`
- All `async` functions use structured concurrency (no unstructured `Task {}` unless coordinating lifecycle)
- `KnowledgeStore` is an actor — all reads/writes are serialised
"""
