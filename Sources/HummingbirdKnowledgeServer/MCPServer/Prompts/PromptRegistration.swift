// Sources/HummingbirdKnowledgeServer/MCPServer/Prompts/PromptRegistration.swift
//
// Registers conversation templates (prompts) on the MCP server.
// Prompts are pre-built conversation starters that guide AI-assisted sessions.

import MCP

/// Registers all MCP prompts on the server.
///
/// Prompts are conversation templates — they give AI clients a structured
/// starting point for common tasks like architecture review or migration.
func registerPrompts(on server: Server) async {
    await server.withMethodHandler(ListPrompts.self) { _ in
        ListPrompts.Result(prompts: [
            Prompt(
                name: "architecture_review",
                description: "Interactive architecture review session for Hummingbird 2.x code. "
                    + "Paste your code and receive violation analysis, pattern explanations, "
                    + "and corrected implementations."
            ),
            Prompt(
                name: "migration_guide",
                description: "Step-by-step guide for migrating a Hummingbird 1.x application to 2.x. "
                    + "Covers renamed types, new middleware protocol, and Swift 6 concurrency changes."
            ),
            Prompt(
                name: "new_endpoint",
                description: "Template for implementing a new Hummingbird 2.x endpoint following "
                    + "clean architecture: route handler, service method, repository method, and DTOs."
            ),
        ])
    }

    await server.withMethodHandler(GetPrompt.self) { params in
        switch params.name {

        case "architecture_review":
            return GetPrompt.Result(
                description: "Architecture review session for Hummingbird 2.x code",
                messages: [
                    .user(
                        """
                        I need you to review my Hummingbird 2.x Swift code for architectural violations.

                        Please:
                        1. Use `check_architecture` to analyse the submitted code
                        2. For each violation, use `explain_pattern` to show the correct approach
                        3. Rewrite any violating sections following the clean architecture rules:
                           - Route handlers are dispatchers only
                           - Service layer has no Hummingbird imports
                           - All dependencies via AppRequestContext
                           - All errors as AppError values
                           - DTOs at every HTTP boundary

                        I'll paste my code now:
                        """
                    ),
                ]
            )

        case "migration_guide":
            return GetPrompt.Result(
                description: "Hummingbird 1.x to 2.x migration guide",
                messages: [
                    .user(
                        """
                        I need to migrate my Hummingbird 1.x application to 2.x.

                        Please:
                        1. Use `check_version_compatibility` on my code to identify breaking changes
                        2. Explain each change with `explain_pattern` using the 2.x pattern ID
                        3. Provide the migrated code for each file

                        Key migration areas to cover:
                        - HBApplication → Application
                        - HBMiddleware → RouterMiddleware protocol with Context typealias
                        - HBRequest/HBResponse → Request/Response
                        - Request context changes
                        - Swift 6 concurrency (actors for shared state)

                        I'll paste my 1.x code now:
                        """
                    ),
                ]
            )

        case "new_endpoint":
            return GetPrompt.Result(
                description: "New Hummingbird 2.x endpoint template",
                messages: [
                    .user(
                        """
                        I need to implement a new Hummingbird 2.x endpoint following clean architecture.

                        Please generate all four layers for this endpoint:
                        1. **Route handler** (controller layer) — dispatcher only, decodes request, returns DTO
                        2. **Service method** — business logic, validates input, calls repository
                        3. **Repository method** — data persistence, no business logic
                        4. **DTOs** — request/response structs, Codable, no domain model exposure

                        Also show:
                        - Where to register the route in Application+build.swift
                        - How the dependency flows through AppRequestContext
                        - The AppError types to use for each failure mode

                        Endpoint description:
                        """
                    ),
                ]
            )

        default:
            throw AppError.promptNotFound(name: params.name)
        }
    }
}
