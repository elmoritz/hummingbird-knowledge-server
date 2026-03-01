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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
                // Update knowledge entry for release
                let entry = KnowledgeEntry(
                    id: "hummingbird-latest-release",
                    title: "Hummingbird Latest Release: \(tagName)",
                    content: "## \(tagName)\n\n\(body.prefix(2000))",
                    layer: nil,
                    patternIds: [],
                    violationIds: [],
                    hummingbirdVersionRange: ">=\(tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v")))",
                    swiftVersionRange: ">=6.0",
                    isTutorialPattern: false,
                    correctionId: nil,
                    confidence: 0.9,
                    source: "github-releases",
                    lastVerifiedAt: Date()
                )
                await store.upsert(entry)
                logger.info("Updated latest release entry", metadata: ["version": "\(tagName)"])

                // Parse release notes for deprecations and generate violation rules
                let parser = ChangelogParser()
                let deprecations = parser.parse(body)

                logger.debug("Parsed release notes", metadata: [
                    "version": "\(tagName)",
                    "deprecations_found": "\(deprecations.count)"
                ])

                if !deprecations.isEmpty {
                    let generator = ViolationRuleGenerator()
                    let releaseVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                    var generatedCount = 0

                    for deprecation in deprecations {
                        let violation = generator.generate(from: deprecation, releaseVersion: releaseVersion)
                        try await store.upsertDynamicViolation(violation)
                        generatedCount += 1

                        logger.debug("Generated violation rule", metadata: [
                            "id": "\(violation.id)",
                            "api": "\(deprecation.deprecatedAPI)",
                            "category": "\(deprecation.category)",
                            "severity": "\(violation.severity)"
                        ])
                    }

                    logger.info("Generated and stored violation rules", metadata: [
                        "version": "\(tagName)",
                        "rules_generated": "\(generatedCount)"
                    ])
                }
            }
        } catch {
            logger.warning("Failed to fetch GitHub release", metadata: ["error": "\(error)"])
        }
    }

    // MARK: - SSWG Index

    private func checkSSWGIndex() async {
        // Fetch SSWG package collection with maturity status
        // Uses hybrid approach: maturity endpoints + package collection for rich metadata

        // Step 1: Fetch maturity status from three endpoints
        let statusMap = await fetchSSWGMaturityStatus()

        // Step 2: Fetch rich package metadata from collection
        let packages = await fetchSSWGPackageCollection()

        // Guard against total failure - preserve cached data
        guard !packages.isEmpty else {
            logger.warning("SSWG index update failed: no packages fetched, preserving cached data")
            return
        }

        // Step 3: Merge and create knowledge entries
        var entries: [KnowledgeEntry] = []
        for package in packages {
            guard let url = package["url"] as? String else {
                logger.debug("Skipping SSWG package with missing URL field")
                continue
            }

            let packageName = extractPackageName(from: url)
            let summary = package["summary"] as? String ?? ""
            let keywords = (package["keywords"] as? [String] ?? []).joined(separator: ", ")
            let status = statusMap[url] ?? "unknown"

            let content = buildPackageContent(
                name: packageName,
                url: url,
                summary: summary,
                keywords: keywords,
                status: status
            )

            let entry = KnowledgeEntry(
                id: "sswg-package-\(packageName.lowercased())",
                title: "SSWG Package: \(packageName)",
                content: content,
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0",
                swiftVersionRange: ">=5.8",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 0.85,
                source: "sswg-index",
                lastVerifiedAt: Date()
            )
            entries.append(entry)
        }

        if !entries.isEmpty {
            await store.upsertAll(entries)
            logger.info("Updated SSWG package entries", metadata: ["count": "\(entries.count)"])
        } else {
            logger.warning("No valid SSWG packages to update, preserving cached data")
        }
    }

    private func fetchSSWGMaturityStatus() async -> [String: String] {
        var statusMap: [String: String] = [:]

        let maturityEndpoints = [
            ("graduated", "https://swift.org/api/v1/sswg/incubation/graduated.json"),
            ("incubating", "https://swift.org/api/v1/sswg/incubation/incubating.json"),
            ("sandbox", "https://swift.org/api/v1/sswg/incubation/sandbox.json"),
        ]

        for (status, urlString) in maturityEndpoints {
            guard let url = URL(string: urlString) else { continue }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    logger.warning("SSWG maturity endpoint returned non-200", metadata: [
                        "status": "\(status)",
                        "url": "\(urlString)",
                    ])
                    continue
                }

                // Parse JSON response
                do {
                    if let urls = try JSONSerialization.jsonObject(with: data) as? [String] {
                        for packageUrl in urls {
                            statusMap[packageUrl] = status
                        }
                        logger.debug("Fetched SSWG maturity level", metadata: [
                            "status": "\(status)",
                            "count": "\(urls.count)",
                        ])
                    } else {
                        logger.warning("SSWG maturity endpoint returned unexpected JSON format", metadata: [
                            "status": "\(status)",
                        ])
                    }
                } catch {
                    logger.warning("Failed to parse SSWG maturity JSON", metadata: [
                        "status": "\(status)",
                        "error": "\(error)",
                    ])
                }
            } catch {
                logger.warning("Failed to fetch SSWG maturity level", metadata: [
                    "status": "\(status)",
                    "error": "\(error)",
                ])
            }
        }

        return statusMap
    }

    private func fetchSSWGPackageCollection() async -> [[String: Any]] {
        let urlString = "https://swiftserver.group/collection/sswg.json"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.warning("SSWG collection endpoint returned non-200", metadata: ["url": "\(urlString)"])
                return []
            }

            // Parse JSON response
            do {
                if let collection = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let packages = collection["packages"] as? [[String: Any]] {
                    logger.debug("Fetched SSWG package collection", metadata: ["count": "\(packages.count)"])
                    return packages
                } else {
                    logger.warning("SSWG collection JSON missing 'packages' array or invalid format")
                    return []
                }
            } catch {
                logger.warning("Failed to parse SSWG collection JSON", metadata: ["error": "\(error)"])
                return []
            }
        } catch {
            logger.warning("Failed to fetch SSWG package collection", metadata: ["error": "\(error)"])
        }

        return []
    }

    private func extractPackageName(from url: String) -> String {
        // Extract package name from Git URL
        // e.g., "https://github.com/apple/swift-nio.git" -> "swift-nio"
        let components = url.split(separator: "/")
        guard let lastComponent = components.last else { return "unknown" }
        return lastComponent.replacingOccurrences(of: ".git", with: "")
    }

    private func buildPackageContent(name: String, url: String, summary: String, keywords: String, status: String) -> String {
        var content = "# \(name)\n\n"
        content += "**SSWG Status:** \(status)\n\n"
        if !summary.isEmpty {
            content += "## Summary\n\n\(summary)\n\n"
        }
        if !keywords.isEmpty {
            content += "**Keywords:** \(keywords)\n\n"
        }
        content += "**Repository:** \(url)\n"
        return content
    }
}
