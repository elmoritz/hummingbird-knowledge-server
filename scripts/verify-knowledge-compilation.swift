#!/usr/bin/env swift

// verify-knowledge-compilation.swift
//
// Verification script that extracts all Swift code examples from knowledge.json
// and attempts to compile them against Hummingbird 2.x to ensure accuracy.

import Foundation

// MARK: - Data Models

struct KnowledgeEntry: Codable {
    let id: String
    let title: String
    let content: String
    let layer: String?
    let hummingbirdVersionRange: String?
    let swiftVersionRange: String?
    let lastVerifiedAt: String?
}

struct CodeExample {
    let entryId: String
    let entryTitle: String
    let code: String
    let isCorrectExample: Bool // true if marked with ✅, false if marked with ❌
    let lineNumber: Int
}

struct CompilationResult {
    let example: CodeExample
    let success: Bool
    let errors: String
}

// MARK: - Code Extraction

func extractCodeExamples(from entries: [KnowledgeEntry]) -> [CodeExample] {
    var examples: [CodeExample] = []

    for entry in entries {
        let lines = entry.content.components(separatedBy: .newlines)
        var inCodeBlock = false
        var currentCode = ""
        var isCorrect = false
        var codeStartLine = 0

        for (index, line) in lines.enumerated() {
            if line.hasPrefix("```swift") {
                inCodeBlock = true
                currentCode = ""
                codeStartLine = index + 1

                // Look back to see if this is a ✅ or ❌ example
                if index > 0 {
                    let previousLine = lines[index - 1]
                    isCorrect = previousLine.contains("✅")
                }
            } else if line.hasPrefix("```") && inCodeBlock {
                inCodeBlock = false
                if !currentCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    examples.append(CodeExample(
                        entryId: entry.id,
                        entryTitle: entry.title,
                        code: currentCode,
                        isCorrectExample: isCorrect,
                        lineNumber: codeStartLine
                    ))
                }
                currentCode = ""
            } else if inCodeBlock {
                currentCode += line + "\n"
            }
        }
    }

    return examples
}

// MARK: - Compilation

func compileCodeExample(_ example: CodeExample) -> CompilationResult {
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = "\(example.entryId)-\(example.lineNumber).swift"
    let filePath = tempDir.appendingPathComponent(fileName)

    // Wrap code with necessary imports and context
    let wrappedCode = """
    import Foundation
    import Hummingbird
    import Logging
    import ServiceLifecycle

    // Code example from: \(example.entryTitle)
    \(example.code)
    """

    do {
        try wrappedCode.write(to: filePath, atomically: true, encoding: .utf8)

        // Attempt compilation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = [
            "-typecheck",
            "-parse-as-library",
            "-suppress-warnings",
            filePath.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Clean up
        try? FileManager.default.removeItem(at: filePath)

        return CompilationResult(
            example: example,
            success: process.terminationStatus == 0,
            errors: output
        )
    } catch {
        // Clean up
        try? FileManager.default.removeItem(at: filePath)

        return CompilationResult(
            example: example,
            success: false,
            errors: "Failed to compile: \(error.localizedDescription)"
        )
    }
}

// MARK: - Reporting

func printResults(_ results: [CompilationResult]) {
    print("═══════════════════════════════════════════════════════════════")
    print("  KNOWLEDGE BASE CODE EXAMPLE COMPILATION VERIFICATION")
    print("═══════════════════════════════════════════════════════════════\n")

    // Separate correct and wrong examples
    let correctResults = results.filter { $0.example.isCorrectExample }
    let wrongResults = results.filter { !$0.example.isCorrectExample }

    // Statistics
    let totalExamples = results.count
    let correctExamplesCount = correctResults.count
    let wrongExamplesCount = wrongResults.count

    let correctExamplesCompiled = correctResults.filter { $0.success }.count
    let correctExamplesFailed = correctResults.filter { !$0.success }.count

    let wrongExamplesCompiled = wrongResults.filter { $0.success }.count
    let wrongExamplesFailed = wrongResults.filter { !$0.success }.count

    // Print summary by entry
    print("COMPILATION RESULTS BY ENTRY:\n")
    print(String(format: "%-45s %12s %12s", "Entry ID", "Type", "Status"))
    print(String(repeating: "─", count: 80))

    let groupedResults = Dictionary(grouping: results) { $0.example.entryId }

    for (entryId, entryResults) in groupedResults.sorted(by: { $0.key < $1.key }) {
        let correctCount = entryResults.filter { $0.example.isCorrectExample && $0.success }.count
        let wrongCount = entryResults.filter { !$0.example.isCorrectExample }.count
        let failedCorrect = entryResults.filter { $0.example.isCorrectExample && !$0.success }.count

        let status = failedCorrect > 0 ? "❌ FAILED" : "✅ PASSED"
        let typeInfo = correctCount > 0 ? "✅×\(correctCount)" : ""
        let wrongInfo = wrongCount > 0 ? "❌×\(wrongCount)" : ""
        let typeStr = [typeInfo, wrongInfo].filter { !$0.isEmpty }.joined(separator: " ")

        print(String(format: "%-45s %12s %12s", entryId, typeStr, status))
    }

    // Print detailed failures
    if correctExamplesFailed > 0 {
        print("\n" + String(repeating: "═", count: 80))
        print("FAILED COMPILATIONS (✅ Examples that should compile):\n")

        for result in correctResults.filter({ !$0.success }) {
            print("Entry: \(result.example.entryId)")
            print("Title: \(result.example.entryTitle)")
            print("Line:  \(result.example.lineNumber)")
            print("\nErrors:")
            print(result.errors)
            print(String(repeating: "─", count: 80))
        }
    }

    // Check for wrong examples that unexpectedly compiled
    if wrongExamplesCompiled > 0 {
        print("\n" + String(repeating: "═", count: 80))
        print("⚠️  WARNING: Wrong examples that compiled (❌ Examples):\n")

        for result in wrongResults.filter({ $0.success }) {
            print("Entry: \(result.example.entryId)")
            print("Title: \(result.example.entryTitle)")
            print("Line:  \(result.example.lineNumber)")
            print("Note:  This example is marked as wrong but compiles successfully")
            print(String(repeating: "─", count: 80))
        }
    }

    // Print summary
    print("\n" + String(repeating: "═", count: 80))
    print("SUMMARY:\n")

    print(String(format: "Total Code Examples:         %d", totalExamples))
    print(String(format: "  ✅ Correct Examples:       %d", correctExamplesCount))
    print(String(format: "  ❌ Wrong Examples:         %d", wrongExamplesCount))
    print()

    if correctExamplesCount > 0 {
        let correctRate = Double(correctExamplesCompiled) / Double(correctExamplesCount) * 100
        print(String(format: "✅ Correct Examples Compiled: %d/%d (%.1f%%)",
                     correctExamplesCompiled, correctExamplesCount, correctRate))
        if correctExamplesFailed > 0 {
            print(String(format: "   ❌ Failed:                %d", correctExamplesFailed))
        }
    }

    if wrongExamplesCount > 0 {
        let wrongFailRate = Double(wrongExamplesFailed) / Double(wrongExamplesCount) * 100
        print(String(format: "❌ Wrong Examples Failed:     %d/%d (%.1f%%)",
                     wrongExamplesFailed, wrongExamplesCount, wrongFailRate))
        if wrongExamplesCompiled > 0 {
            print(String(format: "   ⚠️  Unexpectedly Compiled: %d", wrongExamplesCompiled))
        }
    }

    print()

    // Acceptance criteria
    print(String(repeating: "═", count: 80))
    print("ACCEPTANCE CRITERIA:\n")

    let allCorrectCompile = correctExamplesFailed == 0
    let correctCompilationRate = correctExamplesCount > 0 ?
        Double(correctExamplesCompiled) / Double(correctExamplesCount) * 100 : 100

    let criteriaResults: [(String, Bool)] = [
        ("All ✅ correct examples compile", allCorrectCompile),
        ("Correct example compilation rate >= 95%", correctCompilationRate >= 95.0),
        ("Total examples >= 10", totalExamples >= 10),
    ]

    for (criterion, passed) in criteriaResults {
        print("\(passed ? "✅" : "❌") \(criterion)")
    }

    let allPassed = criteriaResults.allSatisfy { $0.1 }
    print()
    if allPassed {
        print("✅ ALL ACCEPTANCE CRITERIA MET")
    } else {
        print("❌ SOME ACCEPTANCE CRITERIA FAILED")
    }
    print(String(repeating: "═", count: 80))
}

// MARK: - Main Execution

func printUsage() {
    print("""
    verify-knowledge-compilation.swift

    Verifies that all code examples in knowledge.json compile against Hummingbird 2.x.

    USAGE:
        swift verify-knowledge-compilation.swift [OPTIONS]

    OPTIONS:
        --help              Show this help message
        --knowledge-file    Path to knowledge.json (default: ./Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json)
        --verbose           Show detailed compilation output for all examples

    DESCRIPTION:
        This script extracts all Swift code blocks from the knowledge base and attempts
        to compile them. It reports:
        - Which ✅ correct examples compile successfully
        - Which ✅ correct examples fail to compile (indicating broken examples)
        - Which ❌ wrong examples compile (possibly indicating insufficient differences)

    EXAMPLES:
        # Run with default knowledge.json location
        swift scripts/verify-knowledge-compilation.swift

        # Specify custom knowledge file
        swift scripts/verify-knowledge-compilation.swift --knowledge-file /path/to/knowledge.json

        # Show verbose output
        swift scripts/verify-knowledge-compilation.swift --verbose
    """)
}

func main() {
    let args = CommandLine.arguments

    // Handle --help
    if args.contains("--help") || args.contains("-h") {
        printUsage()
        return
    }

    // Parse arguments
    var knowledgeFilePath = "./Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json"
    var verbose = false

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--knowledge-file":
            if i + 1 < args.count {
                knowledgeFilePath = args[i + 1]
                i += 1
            }
        case "--verbose":
            verbose = true
        default:
            print("Unknown option: \(args[i])")
            print("Use --help for usage information")
            return
        }
        i += 1
    }

    // Load knowledge.json
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: knowledgeFilePath)) else {
        print("❌ ERROR: Could not read knowledge file at: \(knowledgeFilePath)")
        return
    }

    guard let entries = try? JSONDecoder().decode([KnowledgeEntry].self, from: data) else {
        print("❌ ERROR: Could not parse knowledge.json")
        return
    }

    print("Loaded \(entries.count) knowledge entries from: \(knowledgeFilePath)\n")

    // Extract code examples
    let examples = extractCodeExamples(from: entries)
    print("Extracted \(examples.count) code examples\n")

    if examples.isEmpty {
        print("⚠️  No code examples found in knowledge base")
        return
    }

    print("Compiling examples...\n")

    // Compile each example
    var results: [CompilationResult] = []
    for (index, example) in examples.enumerated() {
        let progress = String(format: "[%d/%d]", index + 1, examples.count)
        let marker = example.isCorrectExample ? "✅" : "❌"
        print("\(progress) \(marker) \(example.entryId)...", terminator: "")

        let result = compileCodeExample(example)
        results.append(result)

        if result.success {
            print(" ✓")
        } else {
            print(" ✗")
        }

        if verbose && !result.success {
            print(result.errors)
        }
    }

    print()

    // Print results
    printResults(results)
}

// Run the script
main()
