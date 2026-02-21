// Sources/HummingbirdKnowledgeServer/Context/AppRequestContext.swift
//
// The per-request DI container.
// Carries the immutable dependency graph alongside all standard Hummingbird
// request context state. This is the single place where concrete types appear
// at the request level — all other files depend on the context or protocols.

import Hummingbird

/// Per-request context that threads the dependency graph through every handler.
/// DependencyInjectionMiddleware populates `dependencies` at the start of each request.
struct AppRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage

    /// Set by DependencyInjectionMiddleware before any route handler runs.
    /// Declared as IUO so init doesn't require a real AppDependencies at construction time.
    /// If DependencyInjectionMiddleware is missing, the first access crashes with a nil unwrap.
    var dependencies: AppDependencies!

    init(source: Source) {
        self.coreContext = CoreRequestContextStorage(source: source)
    }
}
