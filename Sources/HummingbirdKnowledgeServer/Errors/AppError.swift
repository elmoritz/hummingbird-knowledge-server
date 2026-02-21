// Sources/HummingbirdKnowledgeServer/Errors/AppError.swift
//
// All typed domain errors. Route handlers convert these to HTTPError at the
// HTTP boundary — the service and knowledge base layers never import Hummingbird.

/// Typed domain errors for the knowledge server.
/// Critical violations block code generation; others surface as informational responses.
enum AppError: Error, CustomStringConvertible, Sendable {
    case knowledgeEntryNotFound(id: String)
    case violationBlockedGeneration(violationId: String, description: String)
    case invalidInput(reason: String)
    case internalError(reason: String)
    case resourceNotFound(uri: String)
    case promptNotFound(name: String)

    var description: String {
        switch self {
        case .knowledgeEntryNotFound(let id):
            return "Knowledge entry not found: \(id)"
        case .violationBlockedGeneration(let id, let desc):
            return "Code generation blocked by critical violation '\(id)': \(desc)"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .internalError(let reason):
            return "Internal error: \(reason)"
        case .resourceNotFound(let uri):
            return "Resource not found: \(uri)"
        case .promptNotFound(let name):
            return "Prompt not found: \(name)"
        }
    }
}
