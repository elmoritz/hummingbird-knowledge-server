# hummingbird-knowledge-server

[![CI](https://github.com/elmoritz/hummingbird-knowledge-server/actions/workflows/ci.yml/badge.svg)](https://github.com/elmoritz/hummingbird-knowledge-server/actions/workflows/ci.yml)

An MCP (Model Context Protocol) server that gives AI assistants deep, production-accurate knowledge of [Hummingbird](https://github.com/hummingbird-project/hummingbird) and server-side Swift.

It enforces professional, clean-architecture patterns in every response — routing-layer DTOs, service/repository separation, DI via `RequestContext`, typed errors — and actively flags tutorial-style code as incorrect.

---

## Deployment Models

The server supports two modes, detected automatically from environment variables:

| Mode | Trigger | Auth | Rate limiting | Default bind |
|------|---------|------|--------------|-------------|
| **Local** | `MCP_AUTH_TOKEN` not set | None | Disabled | `127.0.0.1` |
| **Hosted** | `MCP_AUTH_TOKEN` set | Bearer token | 60 req/min | `0.0.0.0` |

You can run your own local instance **and** connect to a shared hosted instance simultaneously — they are independent MCP servers in your client configuration.

---

## Requirements

- Swift 6.0+ / Xcode 16+
- macOS 14+ (local development)
- Linux: Ubuntu 22.04 or Amazon Linux 2023 (hosted deployment)
- Docker (optional, for containerised runs)

---

## Running Locally

```bash
git clone https://github.com/elmoritz/hummingbird-knowledge-server
cd hummingbird-knowledge-server
cp .env.example .env

# Run in release mode — always use this, debug is significantly slower
swift run -c release HummingbirdKnowledgeServer
```

The server starts on `http://localhost:8080`. No authentication is required.

**With Docker:**

```bash
docker compose --profile local up
```

---

## Hosted Deployment

Set `MCP_AUTH_TOKEN` to switch the server into hosted mode:

```bash
# Generate a strong token
openssl rand -hex 32

# Add to .env
echo "MCP_AUTH_TOKEN=<generated_token>" >> .env
echo "GITHUB_TOKEN=<optional_for_higher_rate_limits>" >> .env
```

**With Docker:**

```bash
docker compose --profile hosted up
```

**Build and run directly:**

```bash
docker build -t hummingbird-knowledge-server .
docker run \
  -e MCP_AUTH_TOKEN=your_token \
  -e GITHUB_TOKEN=your_github_token \
  -p 8080:8080 \
  hummingbird-knowledge-server
```

All `/mcp` requests to a hosted instance require:
```
Authorization: Bearer <your_token>
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP port |
| `HOST` | `127.0.0.1` (local) / `0.0.0.0` (hosted) | Bind address |
| `LOG_LEVEL` | `info` | `trace` / `debug` / `info` / `warning` / `error` |
| `MCP_AUTH_TOKEN` | _(none)_ | Sets hosted mode and required Bearer token |
| `RATE_LIMIT_PER_MINUTE` | `60` | Max requests per IP per minute (hosted only) |
| `KNOWLEDGE_UPDATE_INTERVAL` | `3600` | Seconds between auto-updates |
| `GITHUB_TOKEN` | _(none)_ | Raises GitHub API limit from 60 to 5,000 req/hr |
| `REDIS_URL` | _(none)_ | Redis connection URL for distributed rate limiting |
| `REDIS_HOST` | `localhost` | Redis host (if not using `REDIS_URL`) |
| `REDIS_PORT` | `6379` | Redis port (if not using `REDIS_URL`) |
| `REDIS_PASSWORD` | _(none)_ | Redis password (optional) |
| `REDIS_DB` | `0` | Redis database number (optional) |
| `ALERT_WEBHOOK_URL` | _(none)_ | Webhook URL for operational alerts |

---

## Monitoring & Observability

The server includes production-grade monitoring capabilities for operational visibility.

### Metrics Endpoint

**`GET /metrics`** — Prometheus-compatible metrics endpoint (no authentication required)

**Available metrics:**
- Request counts by endpoint (`/mcp`, `/health`, `/ready`, `/metrics`)
- Response latency statistics (mean, p50, p95, p99, min, max)
- Violation detection counts by rule
- Knowledge base entry count
- Last knowledge update timestamp

**Example response:**
```json
{
  "knowledgeEntries": "1247",
  "status": "ok"
}
```

### Enhanced Health Checks

**`GET /health`** — Detailed health status with subsystem checks (no authentication required)

**Health checks:**
- **KnowledgeStore** — Validates knowledge base is loaded and operational
- **GitHub API** — Verifies connectivity to GitHub releases API
- **SSWG Index** — Confirms Swift Server Work Group package index is reachable

**Status codes:**
- `200 OK` — All subsystems healthy
- `503 Service Unavailable` — One or more subsystems degraded/unhealthy

**Example response:**
```json
{
  "status": "healthy",
  "timestamp": "2026-03-02T12:34:56Z",
  "checks": [
    {
      "name": "KnowledgeStore",
      "status": "healthy",
      "message": "Knowledge base loaded with 1247 entries",
      "timestamp": "2026-03-02T12:34:56Z"
    },
    {
      "name": "GitHub API",
      "status": "healthy",
      "message": "GitHub API reachable",
      "timestamp": "2026-03-02T12:34:56Z"
    },
    {
      "name": "SSWG Index",
      "status": "healthy",
      "message": "SSWG package index reachable",
      "timestamp": "2026-03-02T12:34:56Z"
    }
  ]
}
```

**`GET /ready`** — Basic readiness probe for container orchestration

### Prometheus + Grafana Setup

The Docker Compose configuration includes optional Prometheus and Grafana services for metrics collection and visualization.

**Quick start:**

```bash
# Local profile (with automatic Grafana login)
docker compose --profile local up

# Hosted profile (requires GRAFANA_ADMIN_PASSWORD in .env)
docker compose --profile hosted up
```

**Access dashboards:**
- **Grafana:** http://localhost:3000 (admin/admin for local profile)
- **Prometheus:** http://localhost:9090

**Grafana is pre-configured with:**
- Prometheus data source (auto-provisioned)
- Custom dashboards (see `grafana-dashboards.yml`)

**Prometheus configuration:**

The `prometheus.yml` file is pre-configured to scrape metrics from the server every 10 seconds:

```yaml
scrape_configs:
  - job_name: 'hummingbird-knowledge-local'
    static_configs:
      - targets: ['hummingbird-knowledge-local:8080']
    metrics_path: '/metrics'
    scrape_interval: 10s
```

**Production deployment:**

For production, configure Prometheus to scrape your deployed instances:

```yaml
scrape_configs:
  - job_name: 'hummingbird-knowledge-production'
    static_configs:
      - targets: ['your-server:8080']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

### Distributed Rate Limiting

For multi-instance deployments, the server uses Redis for distributed rate limiting to ensure consistent limits across all instances.

**Redis configuration (environment variables):**

```bash
# Single Redis URL (recommended)
REDIS_URL=redis://localhost:6379

# Or individual settings
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your_password  # optional
REDIS_DB=0                     # optional, default: 0
```

**Docker Compose includes Redis:**

```bash
# Local profile — ephemeral storage
docker compose --profile local up

# Hosted profile — persistent storage with AOF
docker compose --profile hosted up
```

**Redis health check:**

The service includes automatic health checks via `redis-cli ping`. The application server waits for Redis to be healthy before starting.

**Rate limit behavior:**
- Tracked per client IP address
- Default: 60 requests per minute (configurable via `RATE_LIMIT_PER_MINUTE`)
- Returns `429 Too Many Requests` when limit exceeded
- Automatically exempt endpoints: `/health`, `/ready`
- Uses sliding window algorithm for accurate limiting

### Alert Webhooks

Configure webhook notifications for operational events:

```bash
# .env
ALERT_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

**Alert events:**
- Knowledge update failures
- Rate limit exhaustion
- Startup failures
- Health check degradation

**Webhook payload format:**

```json
{
  "alert_type": "knowledge_update_failure",
  "severity": "warning",
  "message": "Failed to fetch latest Hummingbird releases from GitHub",
  "timestamp": "2026-03-02T12:34:56Z",
  "details": {
    "error": "API rate limit exceeded",
    "retry_after": "3600"
  }
}
```

**Supported webhook targets:**
- Slack (incoming webhooks)
- Discord (webhook URLs)
- PagerDuty (Events API v2)
- Custom HTTP endpoints (POST with JSON)

### Performance Metrics

**Metrics overhead:**
- Target: <1ms per request
- Implementation: Async actor-based collection
- Memory: Automatic eviction of samples older than 1 hour
- Storage: In-memory (export to Prometheus for persistence)

**Sample retention:**
- Max 1,000 samples per endpoint
- Samples older than 1 hour automatically evicted
- Eviction runs every 5 minutes

---

## CI/CD

The project uses GitHub Actions for automated testing and release management.

### Continuous Integration

The CI workflow runs automatically on:
- Every push to `main`
- Every pull request targeting `main`

**Pipeline stages:**

1. **Lint** — Format checks and Swift 6 language mode verification
2. **Build & Test** — Matrix testing across macOS 14 and Ubuntu 22.04 with:
   - Release builds with warnings-as-errors
   - Parallel test execution
   - Swift package caching for faster builds
   - Code coverage reporting (Linux only)
3. **Docker** — Docker image build verification with health checks
4. **Status Check** — Aggregated CI status for branch protection

All stages must pass before merging to `main`. The pipeline typically completes in under 10 minutes.

### Release Workflow

Tagged releases trigger automated Docker image publishing:

```bash
# Create and push a semantic version tag
git tag v1.0.0
git push origin v1.0.0
```

The release workflow:
1. Extracts version from the tag (e.g., `v1.2.3` → `1.2.3`)
2. Builds multi-platform Docker images (`linux/amd64`, `linux/arm64`)
3. Publishes to GitHub Container Registry (GHCR) with tags:
   - `ghcr.io/elmoritz/hummingbird-knowledge-server:1.2.3` (full version)
   - `ghcr.io/elmoritz/hummingbird-knowledge-server:1.2` (major.minor)
   - `ghcr.io/elmoritz/hummingbird-knowledge-server:1` (major)
   - `ghcr.io/elmoritz/hummingbird-knowledge-server:latest`

Pull the latest release:
```bash
docker pull ghcr.io/elmoritz/hummingbird-knowledge-server:latest
```

---

## Connecting to Claude Desktop

**Local instance (no auth):**

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "hummingbird-knowledge-local": {
      "url": "http://localhost:8080/mcp",
      "transport": "sse"
    }
  }
}
```

**Hosted instance (with auth):**

```json
{
  "mcpServers": {
    "hummingbird-knowledge": {
      "url": "https://mcp.yourdomain.com/mcp",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer your_token_here"
      }
    }
  }
}
```

Restart Claude Desktop after editing. The server must be running before Claude Desktop starts — it connects at launch and does not retry automatically.

---

## IDE Integrations

### VS Code — Continue extension

`.continue/config.json`:

```json
{
  "mcpServers": [
    {
      "name": "hummingbird-knowledge",
      "transport": "sse",
      "url": "http://localhost:8080/mcp"
    }
  ]
}
```

For a hosted instance, add:
```json
"requestOptions": {
  "headers": { "Authorization": "Bearer your_token_here" }
}
```

### Cursor

**Settings → Features → Model Context Protocol → Add:**

```
Name:      hummingbird-knowledge
Type:      SSE
Endpoint:  http://localhost:8080/mcp
```

For hosted, add `Authorization: Bearer your_token_here` in the headers section.

### Zed

`settings.json`:

```json
{
  "context_servers": {
    "hummingbird-knowledge": {
      "transport": "sse",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

### VS Code — Copilot Chat (MCP preview)

`.vscode/mcp.json`:

```json
{
  "servers": {
    "hummingbird-knowledge": {
      "type": "sse",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

---

## Client Compatibility

**✅ Verified Compatible Clients**

| Client | Status | Tools | Resources | Prompts | Configuration |
|--------|--------|-------|-----------|---------|---------------|
| **Claude Desktop** | ✅ Verified | 10/10 | 5/5 | 3/3 | [Example](examples/claude-desktop-config.json) |
| **Cursor** | 📋 Testing | 10/10 | 5/5 | 3/3 | [Example](examples/cursor-config.json) |
| **VS Code Continue** | 📋 Testing | 10/10 | 5/5 | 3/3 | [Example](examples/continue-config.json) |
| **Zed** | 📋 Testing | 10/10 | 5/5 | 3/3 | [Example](examples/zed-settings.json) |
| **VS Code Copilot** | ⚠️ Preview | 10/10 | 5/5 | 3/3 | [Example](examples/vscode-mcp.json) |

**Legend:**
- ✅ Verified — tested and confirmed working
- 📋 Testing — templates prepared, awaiting manual verification
- ⚠️ Preview — experimental support, subject to change

**Server Version:** hummingbird-knowledge-server v0.1.0
**MCP Spec:** 2025-06-18 (Streamable HTTP transport)

For detailed compatibility information, setup instructions, known issues, and troubleshooting:
- **[Full Compatibility Matrix](docs/client-compatibility.md)** — complete feature breakdown per client
- **[Configuration Examples](examples/)** — ready-to-use config files for all clients
- **[Testing Results](docs/testing/)** — detailed test reports for each client

---

## What It Provides

| Primitive | Count | Purpose |
|-----------|-------|---------|
| Tools | 10 | Explain errors, check architecture, generate idiomatic code, diagnose startup failures |
| Resources | 5 | Pitfall catalogue, migration guide, SSWG package index, changelog, code examples |
| Prompts | 3 | Architecture review, debug session, greenfield design |

The server auto-updates its knowledge base hourly from GitHub Releases, the SSWG package index, and the Swift Forums server category.

---

## Architecture

Built on the same patterns it teaches. Every architectural decision in this codebase is an example of production-grade Hummingbird.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full layer reference.

---

## Running Tests

```bash
swift test
```

Tests use `HummingbirdTesting` in `.router` mode — no real network, no port allocation, fast.

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

---

## License

MIT. See [LICENSE](./LICENSE).
