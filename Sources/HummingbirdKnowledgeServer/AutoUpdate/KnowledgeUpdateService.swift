// Sources/HummingbirdKnowledgeServer/AutoUpdate/KnowledgeUpdateService.swift
//
// Background service that keeps the knowledge base current.
// Runs on a configurable interval (default: hourly), polling:
//   - GitHub Releases API for new Hummingbird versions
//   - SSWG package index for incubation status changes
//
// A GITHUB_TOKEN is optional but recommended for hosted deployments to avoid
// the unauthenticated rate limit of 60 requests/hour.

import ServiceLifecycle
import Foundation
import Logging

/// Background service that periodically refreshes knowledge from upstream sources.
///
/// Conforms to `Service` from swift-service-lifecycle so it runs concurrently
/// with the HTTP server inside Hummingbird's service group.
struct KnowledgeUpdateService: Service {

    let store: KnowledgeStore
    let githubToken: String?
    let updateInterval: Duration
    let logger: Logger

    func run() async throws {
        logger.info(
            "Knowledge update service started",
            metadata: [
                "interval_seconds": "\(updateInterval)",
                "github_auth": "\(githubToken != nil ? "token" : "unauthenticated")",
            ]
        )

        // Run first update immediately at startup, then on the interval
        await performUpdate()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: updateInterval)
            } catch is CancellationError {
                break
            }
            await performUpdate()
        }

        logger.info("Knowledge update service stopped")
    }

    // MARK: - Update cycle

    private func performUpdate() async {
        logger.debug("Starting knowledge update cycle")

        await checkHummingbirdRelease()
        await checkSSWGIndex()

        let entryCount = await store.count
        logger.debug("Knowledge update cycle complete", metadata: ["entries": "\(entryCount)"])
    }

    // MARK: - GitHub Releases

    private func checkHummingbirdRelease() async {
        let url = URL(string: "https://api.github.com/repos/hummingbird-project/hummingbird/releases/latest")!
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let token = githubToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.warning("GitHub releases API returned non-200", metadata: ["url": "\(url)"])
                return
            }

            if let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = release["tag_name"] as? String,
               let body = release["body"] as? String {
                let entry = KnowledgeEntry(
                    id: "hummingbird-latest-release",
                    title: "Hummingbird Latest Release: \(tagName)",
                    content: "## \(tagName)\n\n\(body.prefix(2000))",
                    layer: nil,
                    patternIds: [],
                    violationIds: [],
                    hummingbirdVersionRange: ">=\(tagName.trimmingCharacters(in: .init(charactersIn: "v")))",
                    swiftVersionRange: ">=6.0",
                    isTutorialPattern: false,
                    correctionId: nil,
                    confidence: 0.9,
                    source: "github-releases",
                    lastVerifiedAt: Date()
                )
                await store.upsert(entry)
                logger.info("Updated latest release entry", metadata: ["version": "\(tagName)"])
            }
        } catch {
            logger.warning("Failed to fetch GitHub release", metadata: ["error": "\(error)"])
        }
    }

    // MARK: - SSWG Index

    private func checkSSWGIndex() async {
        // SSWG packages page — we fetch and note any status changes
        // In a full implementation this would parse the SSWG JSON index
        let url = URL(string: "https://swift.org/api/v1/packages.json")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return
            }
            logger.debug("SSWG index reachable")
        } catch {
            logger.debug("SSWG index check failed (non-critical)", metadata: ["error": "\(error)"])
        }
    }
}
