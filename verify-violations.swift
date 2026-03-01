#!/usr/bin/env swift

// verify-violations.swift
//
// Verification script that tests architectural violation detection patterns
// against the test cases in test-violations.swift to measure accuracy and
// false-positive rate.

import Foundation

// MARK: - Violation Pattern Testing

struct ViolationTest {
    let id: String
    let pattern: String
    let severity: String
    var positiveTests: [String] = []
    var negativeTests: [String] = []
    var detectedPositives = 0
    var missedPositives = 0
    var falsePositives = 0
    var correctNegatives = 0
}

func runViolationTests() {
    print("═══════════════════════════════════════════════════════════════")
    print("  ARCHITECTURAL VIOLATION DETECTION VERIFICATION")
    print("═══════════════════════════════════════════════════════════════\n")

    // Define all violations to test (extracted from ArchitecturalViolations.swift)
    var tests: [ViolationTest] = [
        // Critical violations
        ViolationTest(id: "inline-db-in-handler",
                     pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.query|pool\.|db\.)"#,
                     severity: "CRITICAL"),
        ViolationTest(id: "service-construction-in-handler",
                     pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*\w+Service\s*\("#,
                     severity: "CRITICAL"),

        // Error violations - Architecture
        ViolationTest(id: "hummingbird-import-in-service",
                     pattern: #"^import\s+Hummingbird"#,
                     severity: "ERROR"),
        ViolationTest(id: "raw-error-thrown-from-handler",
                     pattern: #"throw\s+(?!HTTPError|AppError)\w+Error"#,
                     severity: "ERROR"),
        ViolationTest(id: "business-logic-in-handler",
                     pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(if\s+\w+\s*[<>=!]+|switch\s+\w+|for\s+\w+\s+in|\.calculate|\.compute|\.process(?!DTO))"#,
                     severity: "ERROR"),
        ViolationTest(id: "validation-in-handler",
                     pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(guard\s+[^}]*(\.isEmpty|\.count|\.contains|!\.)|if\s+[^}]*(\.isEmpty|\.count|\.contains|!\.))"#,
                     severity: "ERROR"),
        ViolationTest(id: "data-transformation-in-handler",
                     pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.map\s*\{|\.flatMap\s*\{|\.compactMap\s*\{|\.reduce\(|\.filter\s*\{)"#,
                     severity: "ERROR"),

        // Error violations - DTOs
        ViolationTest(id: "domain-model-across-http-boundary",
                     pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*(?!Response|some ResponseGenerator)\w+Model"#,
                     severity: "ERROR"),
        ViolationTest(id: "domain-entity-across-http-boundary",
                     pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*(?!Response|some ResponseGenerator)\w+Entity"#,
                     severity: "ERROR"),
        ViolationTest(id: "domain-model-array-across-http-boundary",
                     pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*\[\w+(Model|Entity)\]"#,
                     severity: "ERROR"),
        ViolationTest(id: "domain-model-in-request-decode",
                     pattern: #"request\.decode\(as:\s*\w+(Model|Entity)\.self"#,
                     severity: "ERROR"),

        // Error violations - Request Validation
        ViolationTest(id: "missing-request-decode",
                     pattern: #"router\.(post|put|patch).*\{(?!.*request\.decode\(|.*decode\(as:)[^}]{50,}\}"#,
                     severity: "ERROR"),
        ViolationTest(id: "unchecked-uri-parameters",
                     pattern: #"request\.uri\.path(?!\s*(==|!=|\.starts|\.contains))|\blet\s+\w+\s*=\s*request\.uri\.path\b"#,
                     severity: "ERROR"),
        ViolationTest(id: "unchecked-query-parameters",
                     pattern: #"request\.uri\.queryParameters(?!\s*\.isEmpty)|\blet\s+\w+\s*=\s*request\.uri\.queryParameters\[(?!.*guard|.*if let)"#,
                     severity: "ERROR"),
        ViolationTest(id: "raw-parameter-in-service-call",
                     pattern: #"service\.\w+\([^)]*request\.(uri|parameters|headers)\."#,
                     severity: "ERROR"),

        // Error violations - Configuration
        ViolationTest(id: "direct-env-access",
                     pattern: #"(ProcessInfo\.processInfo\.environment\[|getenv\(|ProcessInfo\.environment)"#,
                     severity: "ERROR"),
        ViolationTest(id: "hardcoded-url",
                     pattern: #"(let|var)\s+\w+\s*(:\s*String)?\s*=\s*"https?://[^"]+""#,
                     severity: "ERROR"),
        ViolationTest(id: "hardcoded-credentials",
                     pattern: #"(let|var)\s+\w*(password|secret|key|token|apiKey|apiSecret)\w*\s*=\s*"[^"]+"(?!")"#,
                     severity: "ERROR"),

        // Error violations - Error Handling
        ViolationTest(id: "swallowed-error",
                     pattern: #"catch\s*\{[\s\n]*\}"#,
                     severity: "ERROR"),
        ViolationTest(id: "error-discarded-with-underscore",
                     pattern: #"catch\s+(_|\w+)\s*\{(?!.*logger|.*log\.|.*throw|.*AppError)"#,
                     severity: "ERROR"),
        ViolationTest(id: "generic-error-message",
                     pattern: #"throw\s+\w*Error\("[^"]{1,20}"\)(?!.*:)"#,
                     severity: "ERROR"),
        ViolationTest(id: "print-in-error-handler",
                     pattern: #"catch[^}]*\{[^}]*(print\(|debugPrint\()"#,
                     severity: "ERROR"),
        ViolationTest(id: "missing-error-wrapping",
                     pattern: #"catch\s+let\s+(\w+)\s*\{[^}]*throw\s+\1\s*\}"#,
                     severity: "ERROR"),

        // Error violations - HTTP Response
        ViolationTest(id: "response-without-status-code",
                     pattern: #"Response\s*\([^)]*(?!status:)[^)]*\)"#,
                     severity: "ERROR"),
        ViolationTest(id: "inconsistent-response-format",
                     pattern: #"return\s+Response\s*\([^)]*body:[^)]*"[^"]*"[^)]*\)"#,
                     severity: "ERROR"),
        ViolationTest(id: "response-missing-content-type",
                     pattern: #"Response\s*\([^)]*body:[^)]*\)(?!\s*\.withHeader\s*\(.*content-type)"#,
                     severity: "ERROR"),

        // Error violations - Concurrency
        ViolationTest(id: "sleep-in-handler",
                     pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(sleep\(|Thread\.sleep|usleep\()"#,
                     severity: "ERROR"),
        ViolationTest(id: "blocking-io-in-async",
                     pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(FileHandle\(|FileManager\.default\.(contents|createFile|removeItem|moveItem|copyItem)\(|fopen\(|fread\(|fwrite\()"#,
                     severity: "ERROR"),
        ViolationTest(id: "synchronous-network-call",
                     pattern: #"(URLSession\.shared\.dataTask\(|NSURLConnection\.sendSynchronousRequest|URLSession\(configuration:.*\)\.dataTask\()(?!.*await)"#,
                     severity: "ERROR"),
        ViolationTest(id: "blocking-sleep-in-async",
                     pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(sleep\(|Thread\.sleep|usleep\()"#,
                     severity: "ERROR"),
        ViolationTest(id: "synchronous-database-call-in-async",
                     pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(\.execute\(\)|\.query\()[^}]*(?!await)"#,
                     severity: "ERROR"),
        ViolationTest(id: "global-mutable-state",
                     pattern: #"^(public\s+|internal\s+|private\s+)?var\s+\w+\s*:\s*(?!@Sendable)[^\n]*=(?!\s*\{)"#,
                     severity: "ERROR"),
        ViolationTest(id: "missing-sendable-conformance",
                     pattern: #"(struct|class|enum)\s+\w+(?!.*:\s*.*Sendable)[^{]*(:\s*[^{]*)?(?=\s*\{)"#,
                     severity: "ERROR"),
        ViolationTest(id: "task-detached-without-isolation",
                     pattern: #"Task\.detached\s*\{(?!.*@MainActor|.*actor)"#,
                     severity: "ERROR"),
        ViolationTest(id: "nonisolated-unsafe-usage",
                     pattern: #"nonisolated\s*\(unsafe\)"#,
                     severity: "ERROR"),

        // Warning violations
        ViolationTest(id: "shared-mutable-state-without-actor",
                     pattern: #"var\s+\w+\s*:\s*\[.*\]\s*=\s*\[.*\]"#,
                     severity: "WARNING"),
        ViolationTest(id: "nonisolated-context-access",
                     pattern: #"nonisolated.*context\.\w+"#,
                     severity: "WARNING"),
        ViolationTest(id: "magic-numbers",
                     pattern: #"(timeout|limit|maxConnections|port|bufferSize|retryCount)\s*[=:]\s*\d{2,}"#,
                     severity: "WARNING"),
    ]

    // Read test file
    guard let testFileContent = try? String(contentsOfFile: "./test-violations.swift") else {
        print("❌ ERROR: Could not read test-violations.swift")
        return
    }

    // Parse test file and extract test cases
    let lines = testFileContent.components(separatedBy: .newlines)
    var currentViolationId: String?
    var currentTestType: String? // "positive" or "negative"
    var testCode = ""
    var inFunction = false

    for line in lines {
        // Detect test function start
        if line.contains("func test") {
            // Extract violation ID from function name
            if let match = line.range(of: #"test(\w+(?:-\w+)+)_(Positive|Negative)\d+"#, options: .regularExpression) {
                let funcName = String(line[match])
                let parts = funcName.components(separatedBy: "_")
                if parts.count >= 2 {
                    let violationPart = parts[0].replacingOccurrences(of: "test", with: "")
                    // Convert from camelCase to kebab-case
                    let kebabCase = violationPart.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1-$2", options: .regularExpression).lowercased()
                    currentViolationId = kebabCase
                    currentTestType = parts[1].lowercased()
                    testCode = ""
                    inFunction = true
                }
            }
        }

        if inFunction {
            testCode += line + "\n"

            // Detect function end
            if line.trimmingCharacters(in: .whitespaces) == "}" && !line.contains("router") {
                if let violationId = currentViolationId, let testType = currentTestType {
                    if let index = tests.firstIndex(where: { $0.id == violationId }) {
                        if testType == "positive" {
                            tests[index].positiveTests.append(testCode)
                        } else {
                            tests[index].negativeTests.append(testCode)
                        }
                    }
                }
                inFunction = false
                currentViolationId = nil
                currentTestType = nil
                testCode = ""
            }
        }
    }

    // Run tests
    var totalDetected = 0
    var totalMissed = 0
    var totalFalsePositives = 0
    var totalCorrectNegatives = 0

    for i in 0..<tests.count {
        let regex = try! NSRegularExpression(pattern: tests[i].pattern, options: [.anchorsMatchLines])

        // Test positive cases (should trigger)
        for testCase in tests[i].positiveTests {
            let range = NSRange(testCase.startIndex..., in: testCase)
            if regex.firstMatch(in: testCase, range: range) != nil {
                tests[i].detectedPositives += 1
                totalDetected += 1
            } else {
                tests[i].missedPositives += 1
                totalMissed += 1
            }
        }

        // Test negative cases (should NOT trigger)
        for testCase in tests[i].negativeTests {
            let range = NSRange(testCase.startIndex..., in: testCase)
            if regex.firstMatch(in: testCase, range: range) != nil {
                tests[i].falsePositives += 1
                totalFalsePositives += 1
            } else {
                tests[i].correctNegatives += 1
                totalCorrectNegatives += 1
            }
        }
    }

    // Print results
    print("VIOLATION DETECTION RESULTS:\n")
    print(String(format: "%-45s %8s %10s %10s", "Violation ID", "Severity", "Detected", "Missed"))
    print(String(repeating: "─", count: 80))

    for test in tests {
        if test.positiveTests.count > 0 || test.negativeTests.count > 0 {
            let status = test.missedPositives == 0 && test.falsePositives == 0 ? "✅" :
                        (test.falsePositives > 0 ? "⚠️" : "❌")
            print(String(format: "%s %-43s %8s %7d/%d %7d/%d",
                         status,
                         test.id,
                         test.severity,
                         test.detectedPositives,
                         test.positiveTests.count,
                         test.falsePositives,
                         test.negativeTests.count))
        }
    }

    print("\n" + String(repeating: "═", count: 80))
    print("SUMMARY:\n")

    let totalPositiveTests = totalDetected + totalMissed
    let totalNegativeTests = totalFalsePositives + totalCorrectNegatives
    let totalTests = totalPositiveTests + totalNegativeTests

    let detectionRate = totalPositiveTests > 0 ? Double(totalDetected) / Double(totalPositiveTests) * 100 : 0
    let falsePositiveRate = totalNegativeTests > 0 ? Double(totalFalsePositives) / Double(totalNegativeTests) * 100 : 0
    let accuracy = totalTests > 0 ? Double(totalDetected + totalCorrectNegatives) / Double(totalTests) * 100 : 0

    print(String(format: "Total Violations Defined:    %d", tests.count))
    print(String(format: "Violations with Tests:       %d", tests.filter { $0.positiveTests.count > 0 || $0.negativeTests.count > 0 }.count))
    print()
    print(String(format: "Positive Test Cases:         %d", totalPositiveTests))
    print(String(format: "  ✓ Correctly Detected:      %d (%.1f%%)", totalDetected, detectionRate))
    print(String(format: "  ✗ Missed:                  %d (%.1f%%)", totalMissed, 100 - detectionRate))
    print()
    print(String(format: "Negative Test Cases:         %d", totalNegativeTests))
    print(String(format: "  ✓ Correctly Passed:        %d (%.1f%%)", totalCorrectNegatives, 100 - falsePositiveRate))
    print(String(format: "  ✗ False Positives:         %d (%.1f%%)", totalFalsePositives, falsePositiveRate))
    print()
    print(String(format: "Overall Accuracy:            %.1f%%", accuracy))
    print()

    // Acceptance criteria check
    print(String(repeating: "═", count: 80))
    print("ACCEPTANCE CRITERIA:\n")

    let criteriaResults = [
        ("Total violations >= 20", tests.count >= 20),
        ("False-positive rate < 15%", falsePositiveRate < 15.0),
        ("Detection rate >= 85%", detectionRate >= 85.0),
        ("Overall accuracy >= 90%", accuracy >= 90.0)
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

// Run the tests
runViolationTests()
