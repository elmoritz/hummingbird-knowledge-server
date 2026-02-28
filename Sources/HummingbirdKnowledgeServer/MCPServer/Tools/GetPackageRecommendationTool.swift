// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/GetPackageRecommendationTool.swift
//
// Returns SSWG-vetted Swift package recommendations for a given need.
// Prioritises packages at SSWG Graduated or Incubating status.

import MCP

struct GetPackageRecommendationTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "get_package_recommendation",
            description: "Get SSWG-vetted Swift package recommendations for a given need "
                + "(e.g. 'database', 'authentication', 'logging', 'redis', 'metrics'). "
                + "Prioritises packages at SSWG Graduated or Incubating status.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "need": [
                        "type": "string",
                        "description": "What you need the package for (e.g. 'PostgreSQL database', 'JWT authentication', 'structured logging', 'Redis caching')",
                    ],
                ],
                "required": ["need"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let need) = arguments["need"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'need'")],
                isError: true
            )
        }

        // Fetch SSWG packages from KnowledgeStore (populated by KnowledgeUpdateService)
        let allEntries = await store.allEntries()
        let sswgPackages = allEntries.filter { $0.source == "sswg-index" }

        let lowerNeed = need.lowercased()
        let needTerms = lowerNeed.split(separator: " ").map(String.init)

        // Match packages based on title, content, and keywords
        let matches = sswgPackages.filter { entry in
            let searchableText = "\(entry.title) \(entry.content)".lowercased()
            return needTerms.contains { term in
                searchableText.contains(term)
            }
        }

        var lines: [String] = ["# Package Recommendation: \(need)\n"]

        if matches.isEmpty {
            // Fallback message when no matches found
            if sswgPackages.isEmpty {
                lines.append("SSWG package index is currently loading or unavailable.")
                lines.append("Please try again in a moment, or browse:")
            } else {
                lines.append("No specific SSWG package found for '\(need)'.")
            }
            lines.append("")
            lines.append("**Browse the full index:** https://swift.org/server/packages/")
            lines.append("**SSWG process:** https://github.com/swift-server/sswg")
        } else {
            // Sort matches by confidence, then alphabetically
            let sortedMatches = matches.sorted {
                if $0.confidence != $1.confidence {
                    return $0.confidence > $1.confidence
                }
                return $0.title < $1.title
            }

            for entry in sortedMatches {
                // Extract package name from title (format: "SSWG Package: {name}")
                let packageName = entry.title.replacingOccurrences(of: "SSWG Package: ", with: "")
                lines.append("## \(packageName)")
                lines.append("")

                // Parse and format the content
                let contentLines = entry.content.split(separator: "\n")
                for line in contentLines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                        lines.append(String(line))
                    }
                }
                lines.append("")
            }

            lines.append("---")
            lines.append("Verify current status at: https://swift.org/server/packages/")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
