#!/usr/bin/env swift

// validate-knowledge-entry.swift
//
// Validation script that verifies knowledge entry contributions.
// Checks: required fields, version ranges, confidence values, code compilation,
// and correctionId references for tutorial patterns.

import Foundation

// MARK: - Data Models

struct KnowledgeEntryContribution: Codable {
    let id: String
    let title: String
    let content: String
    let layer: String?
    let patternIds: [String]?
    let violationIds: [String]?
    let hummingbirdVersionRange: String
    let swiftVersionRange: String
    let isTutorialPattern: Bool
    let correctionId: String?
    let confidence: Double
    let source: String
    let lastVerifiedAt: String?
}

struct ExistingKnowledgeEntry: Codable {
    let id: String
    let title: String
}

struct CodeExample {
    let code: String
    let lineNumber: Int
    let isCorrectExample: Bool
}

// MARK: - Validation Results

enum ValidationError {
    case missingFile(String)
    case invalidJSON(String)
    case missingField(String)
    case emptyField(String)
    case invalidLayer(String)
    case invalidVersionRange(String, String)
    case invalidConfidence(Double)
    case missingCorrectionId
    case correctionIdNotFound(String)
    case correctionIdNotNeeded
    case duplicateId(String)
    case codeCompilationFailed(Int, String)
    case emptyContent

    var message: String {
        switch self {
        case .missingFile(let path):
            return "File not found: \(path)"
        case .invalidJSON(let error):
            return "Invalid JSON: \(error)"
        case .missingField(let field):
            return "Missing required field: \(field)"
        case .emptyField(let field):
            return "Field cannot be empty: \(field)"
        case .invalidLayer(let layer):
            return "Invalid layer '\(layer)'. Must be one of: controller, service, repository, model, middleware, configuration, transport, context"
        case .invalidVersionRange(let field, let value):
            return "Invalid version range for \(field): '\(value)'. Must follow semver format (e.g., '>=2.0.0', '>=6.0')"
        case .invalidConfidence(let value):
            return "Invalid confidence value: \(value). Must be between 0.0 and 1.0"
        case .missingCorrectionId:
            return "correctionId is required when isTutorialPattern is true"
        case .correctionIdNotFound(let id):
            return "Correction ID '\(id)' not found in knowledge base"
        case .correctionIdNotNeeded:
            return "correctionId should be null when isTutorialPattern is false"
        case .duplicateId(let id):
            return "Knowledge entry ID '\(id)' already exists in knowledge base"
        case .codeCompilationFailed(let line, let errors):
            return "Code example at line \(line) failed to compile:\n\(errors)"
        case .emptyContent:
            return "Content field cannot be empty"
        }
    }
}

struct ValidationResult {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [String]

    static func success(warnings: [String] = []) -> ValidationResult {
        ValidationResult(isValid: true, errors: [], warnings: warnings)
    }

    static func failure(errors: [ValidationError], warnings: [String] = []) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors, warnings: warnings)
    }
}

// MARK: - Validator

class KnowledgeEntryValidator {

    func validate(filePath: String, skipCompilation: Bool = false) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [String] = []

        // Check file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            return .failure(errors: [.missingFile(filePath)])
        }

        // Load and parse JSON
        let contribution: KnowledgeEntryContribution
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoder = JSONDecoder()
            contribution = try decoder.decode(KnowledgeEntryContribution.self, from: data)
        } catch {
            return .failure(errors: [.invalidJSON(error.localizedDescription)])
        }

        // Validate required fields are not empty
        if contribution.id.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyField("id"))
        }
        if contribution.title.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyField("title"))
        }
        if contribution.content.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyContent)
        }
        if contribution.source.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyField("source"))
        }

        // Validate ID format (kebab-case)
        if !contribution.id.isEmpty && !isKebabCase(contribution.id) {
            warnings.append("ID should use kebab-case format: '\(contribution.id)'")
        }

        // Validate layer if provided
        if let layer = contribution.layer, !layer.isEmpty {
            let validLayers = ["controller", "service", "repository", "model", "middleware", "configuration", "transport", "context"]
            if !validLayers.contains(layer) {
                errors.append(.invalidLayer(layer))
            }
        }

        // Validate version ranges
        if !isValidVersionRange(contribution.hummingbirdVersionRange) {
            errors.append(.invalidVersionRange("hummingbirdVersionRange", contribution.hummingbirdVersionRange))
        }
        if !isValidVersionRange(contribution.swiftVersionRange) {
            errors.append(.invalidVersionRange("swiftVersionRange", contribution.swiftVersionRange))
        }

        // Validate confidence
        if contribution.confidence < 0.0 || contribution.confidence > 1.0 {
            errors.append(.invalidConfidence(contribution.confidence))
        }

        // Validate correctionId logic
        if contribution.isTutorialPattern {
            if contribution.correctionId == nil || contribution.correctionId?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                errors.append(.missingCorrectionId)
            } else if let correctionId = contribution.correctionId {
                if !correctionIdExists(correctionId) {
                    errors.append(.correctionIdNotFound(correctionId))
                }
            }
        } else {
            if contribution.correctionId != nil && !(contribution.correctionId?.isEmpty ?? true) {
                errors.append(.correctionIdNotNeeded)
            }
        }

        // Check for duplicate ID
        if !contribution.id.isEmpty {
            if isDuplicateKnowledgeId(contribution.id) {
                errors.append(.duplicateId(contribution.id))
            }
        }

        // Validate content quality
        if contribution.content.count < 100 {
            warnings.append("Content is quite short (\(contribution.content.count) chars). Consider adding more context.")
        }

        if contribution.title.count < 10 {
            warnings.append("Title is very short (\(contribution.title.count) chars). Consider making it more descriptive.")
        }

        // Extract and validate code examples (unless skipped)
        if !skipCompilation && !contribution.content.isEmpty {
            let codeExamples = extractCodeExamples(from: contribution.content)
            if codeExamples.isEmpty {
                warnings.append("No code examples found. Consider adding Swift code examples to improve clarity.")
            } else {
                // Validate compilation of correct examples (marked with ✅)
                let correctExamples = codeExamples.filter { $0.isCorrectExample }
                for example in correctExamples {
                    if let compilationError = compileCodeExample(example) {
                        errors.append(.codeCompilationFailed(example.lineNumber, compilationError))
                    }
                }

                if !correctExamples.isEmpty {
                    warnings.append("Found \(correctExamples.count) code example(s) marked as correct. Validating compilation...")
                }
            }
        }

        return errors.isEmpty
            ? .success(warnings: warnings)
            : .failure(errors: errors, warnings: warnings)
    }

    private func isKebabCase(_ str: String) -> Bool {
        let kebabPattern = "^[a-z0-9]+(-[a-z0-9]+)*$"
        return str.range(of: kebabPattern, options: .regularExpression) != nil
    }

    private func isValidVersionRange(_ range: String) -> Bool {
        // Check for common semver patterns: >=X.Y.Z, ~>X.Y.Z, ^X.Y.Z, X.Y.Z, >=X.Y
        let patterns = [
            "^>=\\d+\\.\\d+(\\.\\d+)?$",  // >=2.0.0 or >=6.0
            "^~>\\d+\\.\\d+\\.\\d+$",     // ~>2.0.0
            "^\\^\\d+\\.\\d+\\.\\d+$",    // ^2.0.0
            "^\\d+\\.\\d+\\.\\d+$",       // 2.0.0
            "^\\d+\\.\\d+$"               // 2.0
        ]

        return patterns.contains { range.range(of: $0, options: .regularExpression) != nil }
    }

    private func isDuplicateKnowledgeId(_ id: String) -> Bool {
        let knowledgePath = "Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json"

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: knowledgePath)) else {
            return false
        }

        guard let entries = try? JSONDecoder().decode([ExistingKnowledgeEntry].self, from: data) else {
            return false
        }

        return entries.contains { $0.id == id }
    }

    private func correctionIdExists(_ correctionId: String) -> Bool {
        let knowledgePath = "Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json"

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: knowledgePath)) else {
            return false
        }

        guard let entries = try? JSONDecoder().decode([ExistingKnowledgeEntry].self, from: data) else {
            return false
        }

        return entries.contains { $0.id == correctionId }
    }

    private func extractCodeExamples(from content: String) -> [CodeExample] {
        var examples: [CodeExample] = []
        let lines = content.components(separatedBy: .newlines)
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
                        code: currentCode,
                        lineNumber: codeStartLine,
                        isCorrectExample: isCorrect
                    ))
                }
                currentCode = ""
                isCorrect = false
            } else if inCodeBlock {
                currentCode += line + "\n"
            }
        }

        return examples
    }

    private func compileCodeExample(_ example: CodeExample) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "validation-\(UUID().uuidString).swift"
        let filePath = tempDir.appendingPathComponent(fileName)

        // Wrap code with necessary imports
        let wrappedCode = """
        import Foundation
        import Hummingbird
        import Logging
        import ServiceLifecycle

        // Code example validation
        \(example.code)
        """

        do {
            try wrappedCode.write(to: filePath, atomically: true, encoding: .utf8)

            // Attempt compilation
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
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

            if process.terminationStatus != 0 {
                return output.isEmpty ? "Compilation failed with no output" : output
            }

            return nil
        } catch {
            // Clean up
            try? FileManager.default.removeItem(at: filePath)
            return "Failed to compile: \(error.localizedDescription)"
        }
    }
}

// MARK: - Reporting

func printUsage() {
    print("""

    USAGE: validate-knowledge-entry.swift <path-to-json> [options]

    Validates a knowledge entry contribution.

    ARGUMENTS:
      <path-to-json>    Path to JSON file containing knowledge entry

    OPTIONS:
      --help            Show this help message
      --skip-compile    Skip code example compilation (faster, for format checks)

    VALIDATION CHECKS:
      ✓ Required fields present (id, title, content, source)
      ✓ ID follows kebab-case convention
      ✓ Layer is valid (if provided)
      ✓ Version ranges follow semver format
      ✓ Confidence is between 0.0 and 1.0
      ✓ correctionId is required for tutorial patterns
      ✓ correctionId exists in knowledge base (when required)
      ✓ No duplicate knowledge entry IDs
      ✓ Code examples marked with ✅ compile successfully

    JSON FORMAT:
      {
        "id": "unique-entry-id",
        "title": "Entry Title",
        "content": "Detailed content with code examples...",
        "layer": "service",
        "patternIds": [],
        "violationIds": [],
        "hummingbirdVersionRange": ">=2.0.0",
        "swiftVersionRange": ">=6.0",
        "isTutorialPattern": false,
        "correctionId": null,
        "confidence": 0.95,
        "source": "community-contribution",
        "lastVerifiedAt": null
      }

    CODE EXAMPLES:
      Mark correct examples with ✅ on the line before the code block:
        ✅ Correct approach:
        ```swift
        // working code here
        ```

      Mark incorrect examples with ❌:
        ❌ Avoid this:
        ```swift
        // anti-pattern code here
        ```

    EXIT CODES:
      0    Validation passed
      1    Validation failed

    """)
}

func printResult(_ result: ValidationResult, filePath: String) {
    print("═══════════════════════════════════════════════════════════════")
    print("  KNOWLEDGE ENTRY VALIDATION")
    print("═══════════════════════════════════════════════════════════════\n")

    print("File: \(filePath)\n")

    if result.isValid {
        print("✅ VALIDATION PASSED\n")

        if !result.warnings.isEmpty {
            print("Warnings (\(result.warnings.count)):")
            for warning in result.warnings {
                print("  ⚠️  \(warning)")
            }
            print()
        }

        print("All validation checks passed. This knowledge entry is ready to submit.")
    } else {
        print("❌ VALIDATION FAILED\n")

        print("Errors (\(result.errors.count)):")
        for error in result.errors {
            print("  ✗ \(error.message)")
        }
        print()

        if !result.warnings.isEmpty {
            print("Warnings (\(result.warnings.count)):")
            for warning in result.warnings {
                print("  ⚠️  \(warning)")
            }
            print()
        }

        print("Please fix the errors above before submitting.")
    }

    print("═══════════════════════════════════════════════════════════════")
}

// MARK: - Main

let args = CommandLine.arguments

if args.count < 2 || args.contains("--help") || args.contains("-h") {
    printUsage()
    exit(args.contains("--help") || args.contains("-h") ? 0 : 1)
}

let filePath = args[1]
let skipCompilation = args.contains("--skip-compile")

let validator = KnowledgeEntryValidator()
let result = validator.validate(filePath: filePath, skipCompilation: skipCompilation)

printResult(result, filePath: filePath)

exit(result.isValid ? 0 : 1)
