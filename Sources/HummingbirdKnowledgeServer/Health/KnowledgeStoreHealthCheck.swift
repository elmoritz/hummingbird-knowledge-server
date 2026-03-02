// Sources/HummingbirdKnowledgeServer/Health/KnowledgeStoreHealthCheck.swift
//
// Health check for the KnowledgeStore subsystem.
// Verifies that the knowledge base is loaded and contains entries.

import Foundation

/// Health check that verifies KnowledgeStore is loaded and has entries.
struct KnowledgeStoreHealthCheck: HealthCheck {
    private let store: KnowledgeStore

    init(store: KnowledgeStore) {
        self.store = store
    }

    func check() async -> HealthStatus {
        let count = await store.count

        if count > 0 {
            return HealthStatus(
                name: "knowledge_store",
                status: .healthy,
                message: "Knowledge base is loaded",
                metadata: ["entry_count": String(count)]
            )
        } else {
            return HealthStatus(
                name: "knowledge_store",
                status: .unhealthy,
                message: "Knowledge base is empty",
                metadata: ["entry_count": "0"]
            )
        }
    }
}
