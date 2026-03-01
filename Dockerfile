# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM swift:6.0-jammy AS builder

WORKDIR /app

# Copy dependency manifest first so Docker can cache the package resolution layer.
# The resolved versions are committed to the repo for reproducible builds.
COPY Package.swift Package.resolved ./

# Resolve dependencies in a separate layer — only re-runs when Package.swift changes
RUN swift package resolve

# Copy source and build in release mode.
# --static-swift-stdlib embeds the Swift runtime so the final image
# doesn't need the Swift toolchain installed.
COPY Sources ./Sources
COPY Tests ./Tests

RUN swift build \
    --configuration release \
    --static-swift-stdlib \
    -Xswiftc -warnings-as-errors

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
# Minimal Ubuntu image — no Swift toolchain, just what the binary needs at runtime.
FROM ubuntu:22.04

# Install only the runtime libraries the binary actually links against.
# libcurl4 and libxml2 are pulled in by Foundation on Linux.
# ca-certificates is required for HTTPS calls to GitHub API and SSWG index.
# curl is needed for the health check.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libcurl4 \
        libxml2 \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Run as a non-root user — required for most production environments
RUN useradd --system --create-home --shell /bin/false appuser
USER appuser
WORKDIR /home/appuser

# Copy the compiled binary and resource bundle from the build stage
COPY --from=builder \
    /app/.build/release/HummingbirdKnowledgeServer \
    /usr/local/bin/HummingbirdKnowledgeServer
COPY --from=builder \
    /app/.build/release/hummingbird-knowledge-server_HummingbirdKnowledgeServer.resources \
    /usr/local/bin/hummingbird-knowledge-server_HummingbirdKnowledgeServer.resources

# Expose the default port — overridable via PORT environment variable
EXPOSE 8080

# Health check so Docker and Kubernetes know when the container is ready.
# The /health endpoint is always unauthenticated.
HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=10s \
    --retries=3 \
    CMD curl -f http://localhost:${PORT:-8080}/health || exit 1

ENTRYPOINT ["/usr/local/bin/HummingbirdKnowledgeServer"]
