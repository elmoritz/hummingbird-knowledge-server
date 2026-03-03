# Docker Compose Deployment Guide

Deploy the Hummingbird Knowledge Server using Docker Compose. The server is self-contained (no database or cache required) and supports two modes: **local** (no auth) and **hosted** (auth + rate limiting).

---

## Prerequisites

- **Docker Engine** 20.10+ and **Docker Compose** v2+
- At least 4 GB of RAM available to Docker (the Swift build stage is memory-intensive)
- Approximately 2 GB of disk space for the build cache and final image
- A network connection (the build pulls Swift and Ubuntu base images; the server fetches GitHub API data at runtime)

Verify your installation:

```bash
docker --version          # Docker version 20.10+
docker compose version    # Docker Compose version v2+
```

---

## Quick Start

The fastest path to a running instance:

```bash
git clone https://github.com/elmoritz/hummingbird-knowledge-server
cd hummingbird-knowledge-server

# Start in local mode (no auth required)
docker compose --profile local up --build
```

The server is ready when you see the health check pass. Connect your MCP client to:

```
http://localhost:8080/mcp
```

---

## Configuration Reference

All environment variables are defined in `.env.example`. Copy it to get started:

```bash
cp .env.example .env
```

### Shared Variables (Both Modes)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Port the server listens on inside the container |
| `LOG_LEVEL` | `info` | Log verbosity: `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical` |
| `TRANSPORT` | `sse` | MCP transport protocol: `sse` (Server-Sent Events), `http` (HTTP streaming), or `both` |
| `KNOWLEDGE_UPDATE_INTERVAL` | `3600` | Seconds between checks for new Hummingbird releases and SSWG package updates |
| `GITHUB_TOKEN` | _(unset)_ | Optional GitHub personal access token. Raises API rate limit from 60 to 5,000 requests/hr. Recommended for hosted deployments |

### Local Mode Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST` | `127.0.0.1` | Bind address. The default restricts access to the local machine only. Set to `0.0.0.0` to allow LAN access |

### Hosted Mode Variables

Setting `MCP_AUTH_TOKEN` switches the server into hosted mode automatically.

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_AUTH_TOKEN` | _(unset)_ | Bearer token required for all `/mcp` requests. Generate with: `openssl rand -hex 32` |
| `HOST` | `0.0.0.0` | Bind address (defaults to all interfaces in hosted mode) |
| `RATE_LIMIT_PER_MINUTE` | `60` | Maximum MCP requests per client IP per minute |

---

## Deployment Modes

### Local Mode (No Auth)

Best for personal use, development, and testing. No authentication is required.

```bash
docker compose --profile local up
```

- `MCP_AUTH_TOKEN` must **not** be set
- Binds to `127.0.0.1` by default (localhost only)
- Rate limiting is disabled
- Log level defaults to `debug`

### Hosted Mode (Auth + Rate Limiting)

Best for shared or public deployments where you want to protect the server.

```bash
docker compose --profile hosted up
```

- Requires `MCP_AUTH_TOKEN` in your `.env` file
- Binds to `0.0.0.0` (all interfaces)
- Rate limiting is enabled
- Log level defaults to `info`
- All `/mcp` requests require the header: `Authorization: Bearer <token>`

---

## Setting Up `.env`

```bash
cp .env.example .env
```

For **local mode**, the defaults work out of the box. No edits needed.

For **hosted mode**, generate and set a strong auth token:

```bash
# Generate a secure token
openssl rand -hex 32

# Edit .env and set:
MCP_AUTH_TOKEN=<paste-token-here>

# Optional but recommended: set a GitHub token for higher API rate limits
GITHUB_TOKEN=ghp_your_token_here
```

> **Never commit `.env` to version control.** The file is already in `.gitignore`.

---

## Running and Stopping the Service

### Start (foreground)

```bash
# Local mode
docker compose --profile local up --build

# Hosted mode
docker compose --profile hosted up --build
```

### Start (background)

```bash
docker compose --profile local up -d --build
```

### Stop

```bash
# Graceful stop
docker compose --profile local down

# Stop and remove volumes/images
docker compose --profile local down --rmi local
```

### Restart

```bash
docker compose --profile local restart
```

> **Note:** Use `--build` on the first run or after pulling updates to ensure the image is current.

---

## Health Checks

The Dockerfile includes a built-in health check that polls the `/health` endpoint every 30 seconds:

```
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3
  CMD curl -f http://localhost:${PORT:-8080}/health || exit 1
```

The `/health` endpoint is **always unauthenticated**, even in hosted mode.

### Check container health manually

```bash
# Via Docker
docker compose --profile local ps

# Direct HTTP call
curl http://localhost:8080/health
```

### Health check parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `interval` | 30s | Time between checks |
| `timeout` | 5s | Max wait for a response |
| `start_period` | 10s | Grace period after container start |
| `retries` | 3 | Failures before marking unhealthy |

---

## Logs and Debugging

### View logs

```bash
# Follow logs in real time
docker compose --profile local logs -f

# Last 100 lines
docker compose --profile local logs --tail 100
```

### Adjust log level

Set `LOG_LEVEL` in your `.env` or `docker-compose.yml`:

- `debug` — verbose output, useful for development
- `info` — standard operational logging (default for hosted)
- `warning` — only warnings and errors

For temporary debugging of a running container, restart with a different log level:

```bash
LOG_LEVEL=debug docker compose --profile hosted up
```

### Common log messages

| Message | Meaning |
|---------|---------|
| `Server started on ...` | Server is listening and ready |
| `Knowledge update completed` | Successfully fetched latest data from GitHub |
| `Rate limit exceeded` | A client IP hit the per-minute request cap (hosted mode) |

---

## Updating

Pull the latest code and rebuild:

```bash
git pull origin main
docker compose --profile local up -d --build
```

To do a clean rebuild (no cache):

```bash
docker compose --profile local build --no-cache
docker compose --profile local up -d
```

---

## Production Considerations

### Reverse Proxy (TLS Termination)

For public deployments, place a reverse proxy in front of the server to handle TLS. Example with **Caddy** (automatic HTTPS):

```
# Caddyfile
mcp.example.com {
    reverse_proxy localhost:8080
}
```

Example with **nginx**:

```nginx
server {
    listen 443 ssl;
    server_name mcp.example.com;

    ssl_certificate     /etc/letsencrypt/live/mcp.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mcp.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Required for SSE transport
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400s;
    }
}
```

> **Important:** Disable proxy buffering for the SSE transport to work correctly.

### Resource Limits

Add resource constraints to `docker-compose.yml` for production:

```yaml
services:
  hummingbird-knowledge-hosted:
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          memory: 256M
```

### Restart Policy

Both profiles already use `restart: unless-stopped`, which means the container automatically restarts after crashes or host reboots (as long as Docker is running). No changes needed.

### Security

- The container runs as a **non-root user** (`appuser`) by default
- Keep `MCP_AUTH_TOKEN` out of version control and CI logs
- Rotate tokens periodically: generate a new one with `openssl rand -hex 32`, update `.env`, and restart

---

## Connecting MCP Clients

### Claude Desktop

Add to your Claude Desktop MCP configuration (`claude_desktop_config.json`):

**Local instance:**

```json
{
  "mcpServers": {
    "hummingbird-local": {
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

**Hosted instance:**

```json
{
  "mcpServers": {
    "hummingbird-hosted": {
      "url": "https://mcp.example.com/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_MCP_AUTH_TOKEN"
      }
    }
  }
}
```

### Cursor

Add to your Cursor MCP settings (`.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "hummingbird": {
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

For hosted instances, add the `headers` field with the `Authorization` header as shown above.

---

## Troubleshooting

### Container fails to start

**Symptom:** Container exits immediately or enters a restart loop.

**Check logs:**
```bash
docker compose --profile local logs
```

**Common causes:**
- Port 8080 is already in use. Change `PORT` in `.env` and update the port mapping in `docker-compose.yml`.
- Insufficient memory for the build. Allocate at least 4 GB to Docker.

### Health check failing

**Symptom:** `docker compose ps` shows `unhealthy`.

**Diagnose:**
```bash
# Check if the server is responding
curl -v http://localhost:8080/health

# Check container logs for errors
docker compose --profile local logs --tail 50
```

### Cannot connect from MCP client

- **Local mode:** Ensure the client is on the same machine. The default bind address (`127.0.0.1`) rejects external connections.
- **Hosted mode:** Verify `Authorization: Bearer <token>` header is set correctly. The token must match `MCP_AUTH_TOKEN` exactly.
- **Firewall:** Ensure port 8080 (or your custom port) is open.

### Build takes a long time

The first build compiles the Swift project from source, which can take several minutes. Subsequent builds use Docker's layer cache and are much faster. The dependency resolution layer is cached separately, so only source code changes trigger a recompile.

### GitHub API rate limiting

If the server logs show rate-limit errors from the GitHub API, set `GITHUB_TOKEN` in your `.env` file. This increases the limit from 60 to 5,000 requests per hour.

### SSE connections dropping behind a proxy

Ensure your reverse proxy has:
- Proxy buffering **disabled**
- A long read timeout (e.g., `86400s`)
- No response caching

See the [reverse proxy examples](#reverse-proxy-tls-termination) above.
