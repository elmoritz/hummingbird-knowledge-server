# hummingbird-knowledge-server

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
git clone https://github.com/your-org/hummingbird-knowledge-server
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
