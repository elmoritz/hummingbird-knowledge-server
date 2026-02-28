# SSWG API Response Structure Documentation

## Summary

This document describes the actual structure of the SSWG (Swift Server Working Group) package index APIs discovered through investigation.

**Date:** 2026-02-28
**Investigation:** Subtask-1-1 of SSWG Index Integration

## Key Findings

### 1. The URL in Current Code is Incorrect

The current implementation references:
```
https://swift.org/api/v1/packages.json
```

**Status:** This endpoint returns 403 Forbidden and does not exist.

### 2. Actual Available SSWG APIs

The Swift.org SSWG provides **three separate endpoints** organized by maturity level:

#### Graduated Packages
```
https://swift.org/api/v1/sswg/incubation/graduated.json
```

#### Incubating Packages
```
https://swift.org/api/v1/sswg/incubation/incubating.json
```

#### Sandbox Packages
```
https://swift.org/api/v1/sswg/incubation/sandbox.json
```

### 3. Response Structure

All three endpoints return the **same simple structure**:

```json
[
  "https://github.com/apple/swift-nio.git",
  "https://github.com/apple/swift-log.git",
  "https://github.com/swift-server/async-http-client.git",
  ...
]
```

**Format:** JSON array of strings
**Content:** Each element is a Git repository URL
**Protocol:** HTTPS
**Suffix:** `.git` extension on all URLs

#### What's NOT Included

The API responses DO NOT include:
- ❌ Package names (must be extracted from URL)
- ❌ Descriptions
- ❌ Version information
- ❌ Keywords/categories
- ❌ Maturity status (inferred from which endpoint returns the URL)
- ❌ Documentation URLs
- ❌ License information

### 4. Alternative: SSWG Package Collection

For **richer metadata**, the SSWG provides a Package Collection format at:

```
https://swiftserver.group/collection/sswg.json
```

This redirects to:
```
https://raw.githubusercontent.com/swift-server/sswg-collection/main/collection.json
```

#### Collection Format Structure

```json
{
  "formatVersion": "1.0",
  "generatedAt": "2024-08-06T13:39:36Z",
  "generatedBy": { "name": "Swift Server Workgroup" },
  "keywords": ["server", "sswg"],
  "name": "Swift Server Workgroup Collection",
  "overview": "All libraries and tools incubated by the SSWG.",
  "packages": [
    {
      "keywords": ["networking", "nio", "async"],
      "license": {
        "name": "Apache-2.0",
        "url": "https://www.apache.org/licenses/LICENSE-2.0"
      },
      "readmeURL": "https://raw.githubusercontent.com/apple/swift-nio/main/README.md",
      "summary": "Event-driven network application framework for high performance protocol servers & clients, non-blocking.",
      "url": "https://github.com/apple/swift-nio.git",
      "versions": [
        {
          "defaultToolsVersion": "5.8",
          "manifests": {
            "5.8": {
              "packageName": "swift-nio",
              "products": [...],
              "targets": [...],
              "toolsVersion": "5.8",
              "minimumPlatformVersions": [...]
            }
          },
          "version": "2.62.0",
          "summary": "..."
        }
      ]
    }
  ]
}
```

#### Package Entry Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `url` | String | Git repository URL | `"https://github.com/apple/swift-nio.git"` |
| `summary` | String | Brief package description | `"Event-driven network application framework..."` |
| `keywords` | Array[String] | Categorization tags | `["networking", "nio", "async"]` |
| `license` | Object | License name and URL | `{"name": "Apache-2.0", "url": "..."}` |
| `readmeURL` | String | Link to README | GitHub raw README URL |
| `versions` | Array[Object] | Version history with manifests | Complex nested structure |

**Note:** The collection format also **does not explicitly include maturity status** (graduated/incubating/sandbox) in the package objects. This information must be determined by checking which of the three maturity-level endpoints returns the package URL.

## Maturity Level Distribution (as of investigation)

- **Graduated:** 12 packages (SwiftNIO, SwiftLog, SwiftMetrics, PostgresNIO, AsyncHTTPClient, etc.)
- **Incubating:** 12 packages (SwiftPrometheus, Hummingbird, Service Lifecycle, etc.)
- **Sandbox:** 7 packages (RediStack, AWS Lambda Runtime, MQTT NIO, etc.)

**Total:** 31 SSWG-tracked packages

## Implementation Recommendations

### Option 1: Use Maturity-Level Endpoints (Simple)

**Pros:**
- Lightweight responses
- Clear maturity status from endpoint
- Official swift.org API

**Cons:**
- No metadata (name, description, keywords)
- Requires 3 separate API calls
- Must parse package name from Git URL
- No version information

**Best for:** Simple package tracking where maturity status is primary concern

### Option 2: Use Package Collection (Rich)

**Pros:**
- Complete metadata including descriptions, keywords, versions
- Single API call
- Standardized Package Collection format
- License information included

**Cons:**
- Larger response payload (~170+ packages in full SSWG collection)
- No explicit maturity status in package objects
- Still requires correlation with maturity-level endpoints to determine status

**Best for:** Building recommendation tools with rich package information

### Option 3: Hybrid Approach (Recommended)

1. Fetch all three maturity-level endpoints to build status map
2. Fetch the package collection for rich metadata
3. Correlate by URL to assign maturity status to each package
4. Store in KnowledgeStore with all fields

**Implementation:**
```swift
// Fetch maturity status
let graduated = fetch("https://swift.org/api/v1/sswg/incubation/graduated.json")
let incubating = fetch("https://swift.org/api/v1/sswg/incubation/incubating.json")
let sandbox = fetch("https://swift.org/api/v1/sswg/incubation/sandbox.json")

// Build status map
var statusMap: [String: String] = [:]
graduated.forEach { statusMap[$0] = "graduated" }
incubating.forEach { statusMap[$0] = "incubating" }
sandbox.forEach { statusMap[$0] = "sandbox" }

// Fetch rich metadata
let collection = fetch("https://swiftserver.group/collection/sswg.json")

// Merge data
for package in collection.packages {
    let status = statusMap[package.url] ?? "unknown"
    // Create KnowledgeEntry with status + metadata
}
```

## Required Changes to Current Implementation

1. **Update URL:** Change from non-existent `/api/v1/packages.json` to the actual endpoints
2. **Parse Response:** Handle array of URLs instead of expected rich JSON
3. **Extract Package Names:** Parse package name from Git URL path
4. **Consider Collection API:** Evaluate if richer metadata justifies using the collection endpoint

## Sources

- [SSWG Collection Repository](https://github.com/swift-server/sswg-collection)
- [SSWG Incubated Packages](https://www.swift.org/sswg/incubated-packages.html)
- [Swift Package Collections Blog](https://swiftpackageindex.com/blog/introducing-custom-package-collections)
- [SSWG Package Collection](https://raw.githubusercontent.com/swift-server/sswg-collection/main/collection.json)
- [Swift.org SSWG Homepage](https://www.swift.org/sswg/)

---

**Verification Status:** ✅ Manual verification complete
**Next Steps:** Implement parsing logic based on chosen approach (recommend hybrid)
