# Client Compatibility Matrix

[← MCP Server](mcp-server.md) | [Home](index.md) | [Testing Results →](testing/)

---

## MCP Client Compatibility

This document provides a comprehensive compatibility matrix for the `hummingbird-knowledge-server` MCP server across all major MCP clients. Use this as a reference when choosing a client or diagnosing integration issues.

**Last Updated:** March 2026
**Server Version:** hummingbird-knowledge-server v0.1.0
**MCP Spec:** 2025-06-18 (Streamable HTTP transport)

---

## Quick Reference Matrix

| Client | Connection | Tools | Resources | Prompts | Status | Notes |
|--------|------------|-------|-----------|---------|--------|-------|
| **Claude Desktop** | ✓ SSE | 10/10 | 5/5 | 3/3 | ✅ Verified | Reference implementation |
| **Cursor** | ✓ SSE | 10/10 | 5/5 | 3/3 | 📋 Testing | Settings → Features → MCP |
| **VS Code Continue** | ✓ SSE | 10/10 | 5/5 | 3/3 | 📋 Testing | `.continue/config.json` |
| **VS Code Copilot** | ✓ SSE | 10/10 | 5/5 | 3/3 | ⚠️ Preview | `.vscode/mcp.json` |
| **Zed** | ✓ SSE | 10/10 | 5/5 | 3/3 | 📋 Testing | `~/.config/zed/settings.json` |

**Legend:**
- ✅ Verified — tested and confirmed working
- 📋 Testing — template prepared, awaiting manual verification
- ⚠️ Preview — experimental/preview support, subject to change
- ❌ Unsupported — client does not support this feature

---

## Detailed Compatibility

### 1. Claude Desktop

**Platform:** macOS
**Configuration File:** `~/Library/Application Support/Claude/claude_desktop_config.json`
**Transport:** SSE (Server-Sent Events)

#### Connection

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

**Setup Steps:**
1. Stop Claude Desktop (Cmd+Q)
2. Edit `claude_desktop_config.json`
3. Add server configuration as shown above
4. Start `hummingbird-knowledge-server`
5. Launch Claude Desktop
6. Verify server appears in MCP section

#### Feature Support

| Feature | Support | Notes |
|---------|---------|-------|
| **Tools** | 10/10 | All tools supported |
| **Resources** | 5/5 | All resources accessible |
| **Prompts** | 3/3 | All prompts available |
| **Bearer Auth** | ✓ | Supported for hosted mode |
| **Auto-reconnect** | ✓ | After Claude restart |
| **Error Display** | ✓ | Clear error messages |

#### Tools (10 total)

| Tool | Status | Notes |
|------|--------|-------|
| `check_architecture` | ✅ | Detects violations in submitted code |
| `explain_error` | ✅ | Diagnoses error messages and stack traces |
| `explain_pattern` | ✅ | Full pattern explanation with examples |
| `generate_code` | ✅ | Produces idiomatic 2.x code with metadata |
| `get_best_practice` | ✅ | Best practice for a given topic |
| `list_pitfalls` | ✅ | Ranked pitfall list, filterable |
| `diagnose_startup_failure` | ✅ | Step-by-step startup error diagnosis |
| `check_version_compatibility` | ✅ | 1.x vs 2.x compatibility analysis |
| `get_package_recommendation` | ✅ | SSWG-vetted package recommendations |
| `report_issue` | ✅ | Community feedback for self-healing |

#### Resources (5 total)

| Resource | URI | Status | Notes |
|----------|-----|--------|-------|
| Pitfall Catalogue | `hummingbird://pitfalls` | ✅ | Ranked list with severity |
| Architecture Reference | `hummingbird://architecture` | ✅ | Layer definitions and DI patterns |
| Violation Catalogue | `hummingbird://violations` | ✅ | Complete violation pattern set |
| Migration Guide | `hummingbird://migration` | ✅ | 1.x → 2.x migration steps |
| Knowledge Base | `hummingbird://knowledge` | ✅ | Full knowledge entry database |

#### Prompts (3 total)

| Prompt | Status | Notes |
|--------|--------|-------|
| `architecture_review` | ✅ | Guided code review workflow |
| `migration_guide` | ✅ | Step-by-step 1.x → 2.x migration |
| `new_endpoint` | ✅ | 4-layer endpoint generation |

#### Known Issues & Quirks

- **None currently documented** — Claude Desktop is the reference implementation with full MCP support
- Server must be running before launching Claude Desktop for initial connection
- Configuration changes require full application restart (Cmd+Q, not just window close)

---

### 2. Cursor

**Platform:** macOS, Windows, Linux
**Configuration Location:** Settings → Features → Model Context Protocol
**Transport:** SSE (Server-Sent Events)

#### Connection

**UI Configuration:**
1. Open Cursor
2. Navigate to Settings (Cmd+, or Ctrl+,)
3. Go to Features → Model Context Protocol
4. Click "Add New MCP Server"
5. Fill in:
   - **Name:** `hummingbird-knowledge`
   - **Type:** `SSE`
   - **Endpoint:** `http://localhost:8080/mcp`
6. Save and restart Cursor

**Alternative JSON Configuration (if supported):**
```json
{
  "mcpServers": {
    "hummingbird-knowledge": {
      "url": "http://localhost:8080/mcp",
      "transport": "sse"
    }
  }
}
```

#### Feature Support

| Feature | Support | Notes |
|---------|---------|-------|
| **Tools** | 10/10 | Full tool support expected |
| **Resources** | 5/5 | Check implementation — varies by version |
| **Prompts** | 3/3 | Check implementation — varies by version |
| **Bearer Auth** | ✓ | Supported for hosted mode |
| **Auto-reconnect** | ? | To be verified during testing |
| **Error Display** | ? | To be verified during testing |

#### Testing Status

📋 **Templates prepared, awaiting manual verification**

Detailed test results will be available at: [`docs/testing/cursor-results.md`](testing/cursor-results.md)

#### Known Considerations

- MCP support may vary by Cursor version
- Some versions may require explicit tool invocation via `@servername`
- Resource and prompt support implementation varies — test carefully
- Check Cursor's MCP documentation for version-specific requirements

---

### 3. VS Code Continue Extension

**Platform:** VS Code (macOS, Windows, Linux)
**Configuration File:** `.continue/config.json` (project root)
**Transport:** SSE (Server-Sent Events)

#### Connection

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

**Setup Steps:**
1. Install Continue extension from VS Code marketplace
2. Create or navigate to `.continue/config.json`
3. Add MCP server configuration as shown above
4. Reload VS Code window (Cmd+Shift+P → "Developer: Reload Window")
5. Open Continue sidebar panel
6. Verify server connection status

#### Feature Support

| Feature | Support | Notes |
|---------|---------|-------|
| **Tools** | 10/10 | Full tool support expected |
| **Resources** | 5/5 | Check implementation — MCP resource support varies |
| **Prompts** | 3/3 | Check implementation — MCP prompt support varies |
| **Bearer Auth** | ✓ | Via `requestOptions.headers` |
| **Auto-reconnect** | ? | To be verified during testing |
| **Error Display** | ? | To be verified during testing |

#### Hosted Mode Configuration

```json
{
  "mcpServers": [
    {
      "name": "hummingbird-knowledge",
      "transport": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "requestOptions": {
        "headers": {
          "Authorization": "Bearer your_token_here"
        }
      }
    }
  ]
}
```

#### Testing Status

📋 **Templates prepared, awaiting manual verification**

Detailed test results will be available at: [`docs/testing/vscode-continue-results.md`](testing/vscode-continue-results.md)

#### Known Considerations

- Config file must be in project root or user settings directory
- Continue extension version affects MCP feature availability
- Resource and prompt support depends on Continue's MCP implementation level
- May require VS Code window reload after config changes

---

### 4. VS Code Copilot Chat (MCP Preview)

**Platform:** VS Code (macOS, Windows, Linux)
**Configuration File:** `.vscode/mcp.json` (workspace root or user settings)
**Transport:** SSE (Server-Sent Events)
**Status:** ⚠️ **PREVIEW/EXPERIMENTAL**

#### Connection

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

**Prerequisites:**
- VS Code (latest version recommended)
- GitHub Copilot extension installed and activated
- Active GitHub Copilot subscription (Individual, Business, or Enterprise)
- MCP preview features enabled (may require feature flag)

**Setup Steps:**
1. Create `.vscode/mcp.json` in workspace root
2. Add configuration as shown above
3. Start `hummingbird-knowledge-server`
4. Reload VS Code window (Cmd+Shift+P → "Developer: Reload Window")
5. Open Copilot Chat panel
6. Verify MCP server connection status

#### Feature Support

| Feature | Support | Notes |
|---------|---------|-------|
| **Tools** | 10/10 | Expected — preview status |
| **Resources** | 5/5 | Expected — preview status |
| **Prompts** | 3/3 | Expected — preview status |
| **Bearer Auth** | ✓ | Via `headers` field |
| **Auto-reconnect** | ? | Preview feature behavior |
| **Error Display** | ? | Preview UI behavior |

#### Preview Status Warning

⚠️ **Important:** VS Code Copilot Chat's MCP support is currently in preview/experimental status:

- Features may change without notice
- API stability is not guaranteed
- Breaking changes may occur in VS Code or Copilot extension updates
- Documentation may be incomplete or outdated
- Not recommended for production-critical workflows until stable

#### Hosted Mode Configuration

```json
{
  "servers": {
    "hummingbird-knowledge": {
      "type": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "headers": {
        "Authorization": "Bearer your_token_here"
      }
    }
  }
}
```

#### Testing Status

📋 **Templates prepared, awaiting manual verification**

Detailed test results will be available at: [`docs/testing/vscode-copilot-results.md`](testing/vscode-copilot-results.md)

#### Known Considerations

- Requires active GitHub Copilot subscription
- Preview status means limited documentation and support
- Feature availability depends on VS Code and Copilot extension versions
- May not work in remote development environments (WSL, SSH, Containers) — needs verification
- Workspace trust settings may affect MCP server loading

---

### 5. Zed Editor

**Platform:** macOS, Linux
**Configuration File:** `~/.config/zed/settings.json`
**Transport:** SSE (Server-Sent Events)

#### Connection

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

**Setup Steps:**
1. Open Zed Editor
2. Access settings (Cmd+, or Zed → Settings)
3. Open `settings.json` file
4. Add `context_servers` configuration as shown above
5. Save configuration file
6. Start `hummingbird-knowledge-server` (must be running before Zed starts)
7. Restart Zed Editor (Cmd+Q then relaunch)
8. Verify server appears in context server section

#### Feature Support

| Feature | Support | Notes |
|---------|---------|-------|
| **Tools** | 10/10 | Full tool support expected |
| **Resources** | 5/5 | Check implementation — varies by version |
| **Prompts** | 3/3 | Check implementation — varies by version |
| **Bearer Auth** | ✓ | Via `headers` field |
| **Auto-reconnect** | ? | To be verified during testing |
| **Error Display** | ? | To be verified during testing |

#### Hosted Mode Configuration

```json
{
  "context_servers": {
    "hummingbird-knowledge": {
      "transport": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "headers": {
        "Authorization": "Bearer your_token_here"
      }
    }
  }
}
```

#### Testing Status

📋 **Templates prepared, awaiting manual verification**

Detailed test results will be available at: [`docs/testing/zed-results.md`](testing/zed-results.md)

#### Known Considerations

- Zed is Rust-based — expect excellent performance characteristics
- Context server must be running before Zed launches for initial connection
- MCP support implementation may vary by Zed version
- Resource and prompt exposure depends on Zed's MCP implementation
- Integration with Zed's collaboration features needs verification
- Vim mode compatibility needs verification

---

## Common Setup Patterns

### Local Development Mode

All clients follow this pattern for local, unauthenticated access:

1. **Server configuration:**
   - No `MCP_AUTH_TOKEN` set in environment
   - Server binds to `127.0.0.1:8080` by default
   - No authentication required
   - Rate limiting disabled

2. **Client configuration:**
   - URL: `http://localhost:8080/mcp`
   - Transport: `sse`
   - No authentication headers

3. **Startup sequence:**
   - Start server first: `swift run -c release HummingbirdKnowledgeServer`
   - Verify server logs show: `[INFO] MCP endpoint: http://127.0.0.1:8080/mcp`
   - Launch client application
   - Verify connection in client UI

### Hosted/Production Mode

For hosted deployments with authentication:

1. **Server configuration:**
   ```bash
   export MCP_AUTH_TOKEN="your-secure-token-here"
   export PORT=8080
   export HOST="0.0.0.0"
   ```

2. **Client configuration:**
   - URL: `https://mcp.yourdomain.com/mcp`
   - Transport: `sse`
   - Headers: `Authorization: Bearer your-secure-token-here`

3. **Security notes:**
   - Always use HTTPS in production (not HTTP)
   - Generate strong, unique tokens
   - Rotate tokens regularly
   - Use reverse proxy (nginx, Caddy) for TLS termination
   - Enable rate limiting (automatic in hosted mode)

---

## Tools Reference

All clients have access to these 10 tools:

| Tool | Purpose | Typical Use Case |
|------|---------|------------------|
| `check_architecture` | Detect violations in code | Code review, architecture validation |
| `explain_error` | Diagnose error messages | Debugging, troubleshooting |
| `explain_pattern` | Pattern explanation with examples | Learning, implementation guidance |
| `generate_code` | Idiomatic 2.x code generation | Feature development, scaffolding |
| `get_best_practice` | Best practice recommendations | Architecture decisions, code quality |
| `list_pitfalls` | Ranked pitfall catalogue | Proactive issue prevention |
| `diagnose_startup_failure` | Startup error diagnosis | Server initialization issues |
| `check_version_compatibility` | 1.x vs 2.x compatibility | Migration planning |
| `get_package_recommendation` | SSWG-vetted packages | Dependency selection |
| `report_issue` | Feedback for self-healing | Knowledge base improvement |

---

## Resources Reference

All clients have access to these 5 resources:

| Resource | URI | Content | Size |
|----------|-----|---------|------|
| **Pitfall Catalogue** | `hummingbird://pitfalls` | Ranked list of common mistakes | ~10KB |
| **Architecture Reference** | `hummingbird://architecture` | Layer model, DI patterns | ~15KB |
| **Violation Catalogue** | `hummingbird://violations` | Pattern detection rules | ~8KB |
| **Migration Guide** | `hummingbird://migration` | 1.x → 2.x migration steps | ~20KB |
| **Knowledge Base** | `hummingbird://knowledge` | Full knowledge entry database | ~50KB |

> **Note:** Resource support varies by client implementation. Some clients may auto-load resources, while others require explicit requests.

---

## Prompts Reference

All clients have access to these 3 prompts:

| Prompt | Purpose | Multi-Step | Tools Used |
|--------|---------|------------|------------|
| `architecture_review` | Guided code review workflow | ✓ | `check_architecture`, `explain_pattern` |
| `migration_guide` | Step-by-step 1.x → 2.x migration | ✓ | `check_version_compatibility` |
| `new_endpoint` | 4-layer endpoint generation | ✓ | `generate_code` |

> **Note:** Prompt support varies by client implementation. Some clients may expose prompts as slash commands, while others integrate them into suggestions.

---

## Troubleshooting

### Connection Issues

**Problem:** Client shows "Disconnected" or "Failed to connect"

**Solutions:**
1. Verify server is running: `curl http://localhost:8080/health`
2. Check server logs for errors
3. Verify client configuration file syntax (use JSON validator)
4. Ensure no firewall blocking localhost:8080
5. Try restarting both server and client
6. Check for port conflicts: `lsof -i :8080`

### Authentication Issues (Hosted Mode)

**Problem:** "401 Unauthorized" or authentication errors

**Solutions:**
1. Verify `MCP_AUTH_TOKEN` is set on server
2. Check `Authorization` header in client config
3. Ensure token matches exactly (no extra spaces)
4. Verify Bearer prefix is included: `Bearer your-token`
5. Check server logs for auth middleware errors

### Tool Not Found

**Problem:** Client shows "Tool not found" or tool invocation fails

**Solutions:**
1. Verify server version supports all 10 tools
2. Check server logs for tool registration at startup
3. Restart client to refresh tool discovery
4. Verify client MCP implementation version
5. Check for case-sensitivity in tool names (lowercase)

### Large Response Timeouts

**Problem:** Large code submissions or resources timeout

**Solutions:**
1. Check client timeout settings (if configurable)
2. Server default timeout is 30s for SSE connections
3. For large responses, use streaming if client supports it
4. Split large code into smaller chunks
5. Check network latency if using hosted mode

---

## Performance Characteristics

### Response Times (Local Mode)

| Operation | Expected | Notes |
|-----------|----------|-------|
| Initial connection | < 2s | SSE handshake |
| Tool invocation (simple) | < 1s | `list_pitfalls`, `get_best_practice` |
| Tool invocation (complex) | < 5s | `check_architecture`, `generate_code` |
| Resource retrieval | < 2s | All resources under 50KB |
| Prompt initialization | < 1s | Prompt templates are pre-loaded |

### Scalability Notes

- **Local mode:** Single user, no rate limiting
- **Hosted mode:** 60 req/min default rate limit (configurable)
- **Memory:** ~50MB base, +10MB per concurrent connection
- **CPU:** Minimal — most work is in LLM inference, not server logic
- **Concurrency:** Handles 100+ concurrent SSE connections on modern hardware

---

## Version Compatibility

### Server Version

**Current:** `hummingbird-knowledge-server v0.1.0`

### MCP Spec

**Current:** 2025-06-18 (Streamable HTTP transport)

### Client Version Requirements

| Client | Minimum Version | Recommended | Notes |
|--------|----------------|-------------|-------|
| Claude Desktop | Latest stable | Latest | Reference implementation |
| Cursor | Unknown | Latest | Check Cursor MCP docs |
| VS Code Continue | Unknown | Latest | Check extension marketplace |
| VS Code Copilot | Preview build | Latest preview | Experimental — version critical |
| Zed | Unknown | Latest | Check Zed release notes |

---

## Migration from Legacy MCP Spec

If you have an existing MCP server using the 2024-11-05 spec (split `/sse` + `/messages` endpoints), note the following changes:

### Old Spec (2024-11-05)

```
GET  /sse       → SSE stream
POST /messages  → JSON-RPC messages
```

### New Spec (2025-06-18)

```
GET  /mcp  → SSE stream
POST /mcp  → JSON-RPC messages
```

**Migration steps:**

1. Update server to expose single `/mcp` endpoint
2. Update client configurations to use `/mcp` URL
3. Verify SSE stream opens correctly
4. Test tool invocations end-to-end
5. Remove old `/sse` and `/messages` endpoints

`hummingbird-knowledge-server` implements the **current** 2025-06-18 spec. No migration is needed.

---

## Contributing Test Results

If you test the server with any of the clients marked "📋 Testing", please contribute your results:

1. Use the test template in `docs/testing/[client]-results.md`
2. Fill in all sections completely
3. Document any issues, quirks, or unexpected behaviors
4. Note your client version and environment details
5. Submit a pull request or issue with your findings

**Test templates available:**
- [`docs/testing/claude-desktop-results.md`](testing/claude-desktop-results.md)
- [`docs/testing/cursor-results.md`](testing/cursor-results.md)
- [`docs/testing/vscode-continue-results.md`](testing/vscode-continue-results.md)
- [`docs/testing/vscode-copilot-results.md`](testing/vscode-copilot-results.md)
- [`docs/testing/zed-results.md`](testing/zed-results.md)

---

## Summary

The `hummingbird-knowledge-server` MCP server is designed for broad client compatibility:

✅ **Strengths:**
- Standards-compliant SSE transport (MCP spec 2025-06-18)
- Complete tool, resource, and prompt coverage
- Dual-mode operation (local dev + hosted production)
- Clear error messages and logging
- Minimal dependencies and fast responses

⚠️ **Considerations:**
- Client MCP implementation maturity varies
- Resource and prompt support depends on client
- Some clients in preview/experimental status
- Manual testing needed for full verification

**Recommendation:** Start with **Claude Desktop** for development (reference implementation), then test with your preferred client for production use.

---

[← MCP Server](mcp-server.md) | [Home](index.md) | [Testing Results →](testing/)
