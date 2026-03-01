# MCP Server Troubleshooting Guide

[← Client Compatibility](client-compatibility.md) | [Home](index.md) | [References →](references.md)

---

## Comprehensive Troubleshooting for hummingbird-knowledge-server

This guide covers common issues when setting up, configuring, and using the `hummingbird-knowledge-server` MCP server with various clients. Use this as a reference when diagnosing connection problems, authentication failures, and client-specific quirks.

**Last Updated:** March 2026
**Server Version:** hummingbird-knowledge-server v0.1.0
**MCP Spec:** 2025-06-18 (Streamable HTTP transport)

---

## Quick Diagnostic Checklist

Before diving into specific issues, run through this checklist:

- [ ] Server is running: `curl http://localhost:8080/health`
- [ ] Server logs show no errors
- [ ] Client configuration file exists and has valid JSON syntax
- [ ] Server was started **before** launching the client
- [ ] No other process is using port 8080: `lsof -i :8080`
- [ ] Client application has been fully restarted (not just window closed)
- [ ] Configuration file location matches client's expected path

---

## 1. Connection Issues

### Problem: Client Shows "Disconnected" or "Failed to Connect"

**Symptoms:**
- Client UI shows server as "disconnected" or grayed out
- "Failed to connect to MCP server" error messages
- SSE connection errors in server logs
- Client never shows server in available servers list

#### Diagnostic Steps

**Step 1: Verify server is running**

```bash
# Check if server is running
curl http://localhost:8080/health

# Expected response:
# {"status":"ok","timestamp":"2026-03-01T12:00:00Z"}
```

If this fails:
- Server is not running — start it: `swift run -c release HummingbirdKnowledgeServer`
- Port 8080 is blocked by firewall
- Server failed to start (check logs)

**Step 2: Check server logs**

```bash
# Look for these log lines at startup:
# [INFO] Server starting on http://127.0.0.1:8080
# [INFO] MCP endpoint: http://127.0.0.1:8080/mcp
# [INFO] Health check endpoint: http://127.0.0.1:8080/health

# Common error patterns:
# [ERROR] Address already in use → port conflict
# [ERROR] Permission denied → requires elevated privileges
# [ERROR] Failed to bind → network configuration issue
```

**Step 3: Verify port availability**

```bash
# Check if port 8080 is already in use
lsof -i :8080

# If another process is using it, either:
# 1. Stop that process
# 2. Run server on different port:
export PORT=8081
swift run -c release HummingbirdKnowledgeServer

# Then update client config to use http://localhost:8081/mcp
```

**Step 4: Validate client configuration**

```bash
# Validate JSON syntax (example for Claude Desktop on macOS)
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json | python3 -m json.tool

# Expected: pretty-printed JSON
# Error: indicates syntax error in configuration file
```

#### Solutions by Client

**Claude Desktop (macOS):**

1. Verify configuration file exists and is valid JSON:
   ```bash
   cat ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```

2. Configuration must include:
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

3. **Critical:** Fully quit Claude Desktop (Cmd+Q), then relaunch
   - Simply closing the window is **not** sufficient
   - Server must be running **before** launching Claude Desktop

4. Check Claude Desktop logs (if available in application menu)

**Cursor:**

1. Navigate to Settings → Features → Model Context Protocol
2. Verify server entry exists with:
   - Name: `hummingbird-knowledge` (or your chosen name)
   - Type: `SSE`
   - Endpoint: `http://localhost:8080/mcp`
3. Save and fully restart Cursor (not just reload window)
4. Check Cursor's developer console for errors (if available)

**VS Code Continue:**

1. Verify `.continue/config.json` exists in project root or user settings directory
2. Configuration must use array syntax:
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
3. Reload VS Code window: Cmd+Shift+P → "Developer: Reload Window"
4. Open Continue sidebar and check connection status
5. Check VS Code's Output panel → Continue for diagnostic messages

**VS Code Copilot (Preview):**

1. Verify `.vscode/mcp.json` exists in workspace root or user settings
2. Configuration structure differs from Continue:
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
3. Ensure GitHub Copilot subscription is active
4. Check VS Code version supports MCP preview features
5. Reload window and verify in Output panel → GitHub Copilot

**Zed:**

1. Verify `~/.config/zed/settings.json` contains:
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
2. Server must be running **before** launching Zed
3. Fully quit Zed (Cmd+Q) and relaunch
4. Check Zed's log panel for connection errors

#### Network-Level Debugging

```bash
# Monitor HTTP requests to the server
# Terminal 1: Start server with debug logging
LOG_LEVEL=debug swift run -c release HummingbirdKnowledgeServer

# Terminal 2: Monitor traffic
sudo tcpdump -i lo0 -A 'tcp port 8080'

# Terminal 3: Test SSE connection manually
curl -N -H "Accept: text/event-stream" http://localhost:8080/mcp

# Expected: SSE stream with initialization events
# Error: connection refused, timeout, or HTTP error
```

---

## 2. Authentication Problems

### Problem: "401 Unauthorized" or Authentication Errors (Hosted Mode)

**Symptoms:**
- Client shows "Unauthorized" or "Authentication failed"
- Server logs show `401` responses
- Tools work in local mode but fail in hosted mode
- "Invalid token" error messages

#### Diagnostic Steps

**Step 1: Verify server authentication configuration**

```bash
# Check if MCP_AUTH_TOKEN is set
echo $MCP_AUTH_TOKEN

# If empty, authentication is disabled (local mode only)
# For hosted mode, set a secure token:
export MCP_AUTH_TOKEN="your-secure-token-here"
```

**Step 2: Verify client authentication header**

The header format varies by client:

**Claude Desktop:**
```json
{
  "mcpServers": {
    "hummingbird-knowledge": {
      "url": "https://mcp.yourdomain.com/mcp",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer your-secure-token-here"
      }
    }
  }
}
```

**VS Code Continue:**
```json
{
  "mcpServers": [
    {
      "name": "hummingbird-knowledge",
      "transport": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "requestOptions": {
        "headers": {
          "Authorization": "Bearer your-secure-token-here"
        }
      }
    }
  ]
}
```

**VS Code Copilot:**
```json
{
  "servers": {
    "hummingbird-knowledge": {
      "type": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "headers": {
        "Authorization": "Bearer your-secure-token-here"
      }
    }
  }
}
```

**Zed:**
```json
{
  "context_servers": {
    "hummingbird-knowledge": {
      "transport": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "headers": {
        "Authorization": "Bearer your-secure-token-here"
      }
    }
  }
}
```

**Step 3: Test authentication manually**

```bash
# Test without auth (should fail with 401)
curl -i http://localhost:8080/mcp

# Test with auth (should succeed)
curl -i -H "Authorization: Bearer your-token-here" http://localhost:8080/mcp

# Expected response headers:
# HTTP/1.1 200 OK
# Content-Type: text/event-stream
```

#### Common Authentication Mistakes

| Mistake | Example | Fix |
|---------|---------|-----|
| **Missing "Bearer" prefix** | `"Authorization": "your-token"` | `"Authorization": "Bearer your-token"` |
| **Extra whitespace** | `"Bearer  token"` (2 spaces) | `"Bearer token"` (1 space) |
| **Token mismatch** | Server uses token A, client uses token B | Ensure exact match |
| **Wrong header location** | Header in wrong config section | See client-specific examples above |
| **Quotes in token** | `"Bearer 'token'"` | `"Bearer token"` (no quotes) |
| **Environment variable not set** | Forgot `export MCP_AUTH_TOKEN` | Set before starting server |
| **Token not loaded** | Set token after server start | Restart server after setting token |

#### Security Best Practices

When using authentication in hosted mode:

1. **Generate strong tokens:**
   ```bash
   # Generate a secure random token
   openssl rand -base64 32
   ```

2. **Use environment variables, not hardcoded values:**
   ```bash
   # Bad: hardcoding in config files committed to git
   # Good: use environment variables or secrets management
   export MCP_AUTH_TOKEN="$(cat /path/to/secure/token/file)"
   ```

3. **Rotate tokens regularly:**
   - Set calendar reminder to rotate every 90 days
   - Update server environment variable
   - Update all client configurations
   - Test connections after rotation

4. **Use HTTPS in production:**
   ```bash
   # Bad: http://mcp.example.com (token sent in clear text)
   # Good: https://mcp.example.com (token encrypted in transit)
   ```

5. **Restrict network access:**
   ```bash
   # Use firewall rules to restrict access to known client IPs
   # Example with ufw:
   sudo ufw allow from CLIENT_IP to any port 8080
   ```

---

## 3. Server Not Running Errors

### Problem: Server Fails to Start or Crashes Immediately

**Symptoms:**
- `swift run` command exits immediately
- "Address already in use" errors
- Compilation errors
- Silent failures with no output

#### Diagnostic Steps

**Step 1: Check compilation**

```bash
# Clean build
swift package clean
swift build -c release

# Look for compilation errors:
# - Missing dependencies
# - Swift version mismatch
# - Syntax errors
```

**Step 2: Verify Swift and package versions**

```bash
# Check Swift version (requires 6.0+)
swift --version
# Expected: Swift version 6.0 or later

# Check package dependencies
swift package show-dependencies

# Update dependencies if needed
swift package update
```

**Step 3: Check configuration**

```bash
# Run with explicit configuration
export LOG_LEVEL=debug
export PORT=8080
export HOST=127.0.0.1
swift run -c release HummingbirdKnowledgeServer

# Watch for configuration errors:
# [ERROR] Invalid configuration: ...
# [ERROR] Required environment variable missing: ...
```

**Step 4: Check logs and error output**

```bash
# Run with full logging
swift run -c release HummingbirdKnowledgeServer 2>&1 | tee server.log

# Common startup errors:
# - Port already in use → change PORT
# - Permission denied → check file permissions
# - Module not found → swift package clean && swift build
```

#### Common Startup Issues

| Error | Cause | Solution |
|-------|-------|----------|
| **"Address already in use"** | Port 8080 occupied | `lsof -i :8080` then kill process or use different port |
| **"Module 'Hummingbird' not found"** | Dependencies not resolved | `swift package resolve && swift build` |
| **Silent exit with code 1** | Uncaught exception at startup | Run with `LOG_LEVEL=debug` for stack trace |
| **"Permission denied" (port < 1024)** | Attempting to bind privileged port | Use port ≥ 1024 or run with sudo (not recommended) |
| **Segmentation fault** | Memory corruption or Swift bug | Update Swift version, check for known issues |
| **"No such file or directory"** | Working directory issue | Run from package root |

#### Platform-Specific Issues

**macOS:**

```bash
# Check if Xcode command line tools are installed
xcode-select -p

# If not installed:
xcode-select --install

# Update to latest Swift toolchain
# Download from: https://swift.org/download/
```

**Linux:**

```bash
# Check Swift installation
which swift

# Verify required system libraries
ldd .build/release/HummingbirdKnowledgeServer

# Common missing dependencies on Ubuntu/Debian:
sudo apt-get update
sudo apt-get install libssl-dev libz-dev

# On RHEL/CentOS:
sudo yum install openssl-devel zlib-devel
```

**Docker:**

```bash
# If running in Docker, ensure proper base image
# Dockerfile should use Swift 6.0+ base:
FROM swift:6.0

# Check Docker logs
docker logs <container-id>

# Run interactively for debugging
docker run -it --rm -p 8080:8080 your-image /bin/bash
```

---

## 4. Configuration Validation

### Problem: Invalid or Malformed Configuration

**Symptoms:**
- Client ignores server configuration
- Server starts but client can't connect
- Syntax errors in config files
- "Unexpected token" or "Parse error" messages

#### JSON Validation by Client

**Claude Desktop (macOS):**

```bash
# Location
CONFIG_FILE=~/Library/Application\ Support/Claude/claude_desktop_config.json

# Validate JSON syntax
cat "$CONFIG_FILE" | python3 -m json.tool

# Check for common mistakes
# 1. Missing commas between objects
# 2. Trailing commas (invalid in strict JSON)
# 3. Unescaped quotes in strings
# 4. Wrong nesting levels

# Example of valid configuration:
cat <<'EOF' > "$CONFIG_FILE"
{
  "mcpServers": {
    "hummingbird-knowledge": {
      "url": "http://localhost:8080/mcp",
      "transport": "sse"
    }
  }
}
EOF
```

**VS Code (Continue or Copilot):**

```bash
# Continue config location
CONFIG_FILE=.continue/config.json

# Copilot config location
CONFIG_FILE=.vscode/mcp.json

# Validate with jq
cat "$CONFIG_FILE" | jq .

# Expected: pretty-printed JSON
# Error: parse error at line X, column Y
```

**Zed:**

```bash
# Config location
CONFIG_FILE=~/.config/zed/settings.json

# Validate
cat "$CONFIG_FILE" | python3 -m json.tool

# Note: Zed settings.json may contain comments
# Use a JSON5 validator if standard JSON validation fails
```

#### Common Configuration Mistakes

| Issue | Invalid Example | Valid Example |
|-------|----------------|---------------|
| **Trailing comma** | `{"url": "...",}` | `{"url": "..."}` |
| **Missing quotes** | `{url: "..."}` | `{"url": "..."}` |
| **Wrong transport** | `"transport": "http"` | `"transport": "sse"` |
| **Missing protocol** | `"url": "localhost:8080/mcp"` | `"url": "http://localhost:8080/mcp"` |
| **Wrong endpoint** | `"url": "http://localhost:8080"` | `"url": "http://localhost:8080/mcp"` |
| **Array vs object** | Varies by client | See client-specific docs |
| **Mixed quotes** | `"url': "..."` (mixed ' and ") | `"url": "..."` (consistent ") |

#### Configuration Templates

**Claude Desktop — Complete Valid Config:**

```json
{
  "mcpServers": {
    "hummingbird-knowledge-local": {
      "url": "http://localhost:8080/mcp",
      "transport": "sse"
    },
    "hummingbird-knowledge-hosted": {
      "url": "https://mcp.yourdomain.com/mcp",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer your-token-here"
      }
    }
  }
}
```

**VS Code Continue — Complete Valid Config:**

```json
{
  "mcpServers": [
    {
      "name": "hummingbird-knowledge-local",
      "transport": "sse",
      "url": "http://localhost:8080/mcp"
    },
    {
      "name": "hummingbird-knowledge-hosted",
      "transport": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "requestOptions": {
        "headers": {
          "Authorization": "Bearer your-token-here"
        }
      }
    }
  ]
}
```

**VS Code Copilot — Complete Valid Config:**

```json
{
  "servers": {
    "hummingbird-knowledge-local": {
      "type": "sse",
      "url": "http://localhost:8080/mcp"
    },
    "hummingbird-knowledge-hosted": {
      "type": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "headers": {
        "Authorization": "Bearer your-token-here"
      }
    }
  }
}
```

**Zed — Complete Valid Config:**

```json
{
  "context_servers": {
    "hummingbird-knowledge-local": {
      "transport": "sse",
      "url": "http://localhost:8080/mcp"
    },
    "hummingbird-knowledge-hosted": {
      "transport": "sse",
      "url": "https://mcp.yourdomain.com/mcp",
      "headers": {
        "Authorization": "Bearer your-token-here"
      }
    }
  }
}
```

---

## 5. Client-Specific Quirks

### Claude Desktop

**Quirk 1: Requires full application quit**

- **Issue:** Configuration changes not detected after window close
- **Solution:** Always use Cmd+Q (macOS) or equivalent full quit, not just window close

**Quirk 2: Server must start before client**

- **Issue:** Connection fails if client launches first
- **Solution:** Start server, verify it's running, then launch Claude Desktop

**Quirk 3: Configuration file location is platform-specific**

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux:** `~/.config/Claude/claude_desktop_config.json`

**Quirk 4: No visible error messages for config syntax errors**

- **Issue:** Invalid JSON silently ignored
- **Solution:** Always validate JSON syntax before restarting

### Cursor

**Quirk 1: MCP support varies by version**

- **Issue:** Older Cursor versions may have limited or no MCP support
- **Solution:** Update to latest stable version

**Quirk 2: Settings UI vs JSON config**

- **Issue:** Some versions use UI, others use JSON file
- **Solution:** Check Cursor documentation for your version

**Quirk 3: Explicit tool invocation required**

- **Issue:** Tools may not auto-suggest; need `@servername` syntax
- **Solution:** Use `@hummingbird-knowledge` prefix when invoking tools

**Quirk 4: Feature flag requirement**

- **Issue:** MCP support may be behind feature flag
- **Solution:** Enable in Settings → Features → Model Context Protocol

### VS Code Continue

**Quirk 1: Config file location varies**

- **Issue:** Can be project-local or user-global
- **Solution:** Project: `.continue/config.json`, User: `~/.continue/config.json`

**Quirk 2: Array syntax required**

- **Issue:** `mcpServers` must be an array, not object
- **Solution:** Use `[{...}]` not `{...}`

**Quirk 3: Window reload required**

- **Issue:** Config changes not detected without reload
- **Solution:** Cmd+Shift+P → "Developer: Reload Window" after config changes

**Quirk 4: Extension version critical**

- **Issue:** MCP support added in recent versions only
- **Solution:** Update Continue extension to latest version

### VS Code Copilot (Preview)

**Quirk 1: Experimental status**

- **Issue:** Features may change or break without notice
- **Solution:** Pin to specific VS Code and Copilot extension versions

**Quirk 2: Requires active subscription**

- **Issue:** MCP features disabled without active Copilot subscription
- **Solution:** Verify subscription at https://github.com/settings/copilot

**Quirk 3: Limited documentation**

- **Issue:** Official docs may be incomplete or outdated
- **Solution:** Check VS Code release notes and GitHub discussions

**Quirk 4: Remote development limitations**

- **Issue:** MCP may not work in WSL, SSH, or container environments
- **Solution:** Test in each environment; use local VS Code if remote fails

**Quirk 5: Workspace trust required**

- **Issue:** Untrusted workspaces may block MCP server loading
- **Solution:** Trust the workspace in VS Code settings

### Zed

**Quirk 1: Server must run before Zed launch**

- **Issue:** Connection fails if Zed starts first
- **Solution:** Start server, then launch Zed

**Quirk 2: Platform availability**

- **Issue:** Zed not available on all platforms
- **Solution:** macOS and Linux only (as of March 2026)

**Quirk 3: Config location is user-global only**

- **Issue:** No per-project MCP server configuration
- **Solution:** All projects use `~/.config/zed/settings.json`

**Quirk 4: MCP implementation maturity**

- **Issue:** Zed's MCP support is newer; features may be limited
- **Solution:** Test all tools, resources, and prompts explicitly

**Quirk 5: Vim mode interactions**

- **Issue:** Vim mode key bindings may conflict with MCP invocations
- **Solution:** Verify tool invocation methods in Vim mode

---

## 6. Tool Invocation Issues

### Problem: "Tool Not Found" or Tool Execution Fails

**Symptoms:**
- Client shows "Tool not found" error
- Tool appears in list but fails when invoked
- Partial tool output or timeout
- "Invalid parameters" errors

#### Diagnostic Steps

**Step 1: Verify tool registration**

```bash
# Check server logs at startup for tool registration
# Expected log lines:
# [INFO] Registering MCP tool: check_architecture
# [INFO] Registering MCP tool: explain_error
# ... (10 tools total)

# If tools not registered:
# 1. Check server version (should be v0.1.0+)
# 2. Verify compilation succeeded
# 3. Check for errors in ToolRegistration.swift
```

**Step 2: List available tools**

Use the client's tool discovery mechanism:

- **Claude Desktop:** Tools appear automatically in suggestions
- **Cursor:** Type `@hummingbird-knowledge` to see tool list
- **VS Code Continue:** Tools appear in Continue sidebar
- **VS Code Copilot:** Tools integrate into Copilot Chat suggestions
- **Zed:** Check context server panel for tool list

**Step 3: Test tool manually with curl**

```bash
# Test tool invocation via JSON-RPC
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "list_pitfalls",
      "arguments": {}
    }
  }'

# Expected: JSON response with pitfall list
# Error: indicates server-side tool execution issue
```

**Step 4: Check tool parameters**

Common parameter mistakes:

| Tool | Common Mistake | Correct Usage |
|------|---------------|---------------|
| `check_architecture` | Missing `code` parameter | `{"code": "..."}` |
| `explain_error` | Not escaping newlines | Use proper JSON escaping |
| `generate_code` | Invalid layer name | Use: service, repository, controller, etc. |
| `list_pitfalls` | Invalid severity filter | Use: critical, error, warning |

#### Solutions

**Solution 1: Verify tool name case**

- Tool names are **lowercase** with underscores
- `check_architecture` ✓
- `checkArchitecture` ✗
- `check-architecture` ✗

**Solution 2: Check parameter types**

```json
// Correct: string parameter
{"code": "router.get(\"/\") { ... }"}

// Incorrect: object instead of string
{"code": {"content": "..."}}
```

**Solution 3: Handle large payloads**

For large code submissions:
- Client may have size limits (check client docs)
- Server has 30s timeout for SSE connections
- Break large code into smaller chunks
- Use streaming if client supports it

---

## 7. Resource Access Issues

### Problem: Resources Not Loading or Inaccessible

**Symptoms:**
- Resources don't appear in client UI
- "Resource not found" errors
- Empty resource content
- Timeout fetching resources

#### Diagnostic Steps

**Step 1: Verify client resource support**

| Client | Resource Support | Notes |
|--------|-----------------|-------|
| Claude Desktop | ✅ Full | All 5 resources accessible |
| Cursor | ⚠️ Varies | Check version-specific support |
| VS Code Continue | ⚠️ Varies | May require explicit requests |
| VS Code Copilot | ⚠️ Preview | Limited documentation |
| Zed | ⚠️ Varies | Implementation maturity varies |

**Step 2: Test resource access manually**

```bash
# Test resource retrieval via JSON-RPC
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "resources/read",
    "params": {
      "uri": "hummingbird://pitfalls"
    }
  }'

# Expected: JSON response with resource content
```

**Step 3: Verify resource URIs**

Valid resource URIs:
- `hummingbird://pitfalls` — Pitfall catalogue
- `hummingbird://architecture` — Architecture reference
- `hummingbird://violations` — Violation catalogue
- `hummingbird://migration` — Migration guide
- `hummingbird://knowledge` — Full knowledge base

Common mistakes:
- `hummingbird:/pitfalls` (missing slash) ✗
- `hummingbird://pitfall` (missing 's') ✗
- `http://hummingbird/pitfalls` (wrong protocol) ✗

#### Client-Specific Resource Behavior

**Claude Desktop:**
- Resources auto-load on connection
- Accessible via resource browser in UI
- Updates automatically if server restarts

**Other Clients:**
- May require explicit resource requests
- May not display resources in UI
- May need to query resources programmatically

---

## 8. Performance and Timeout Issues

### Problem: Slow Responses or Timeouts

**Symptoms:**
- Tool invocations take longer than expected
- SSE connection drops after period of inactivity
- "Request timeout" errors
- Client shows loading spinner indefinitely

#### Performance Expectations

| Operation | Expected Time | Notes |
|-----------|--------------|-------|
| Initial connection | < 2s | SSE handshake |
| Simple tools | < 1s | `list_pitfalls`, `get_best_practice` |
| Complex tools | < 5s | `check_architecture`, `generate_code` |
| Resources | < 2s | All resources under 50KB |
| Prompts | < 1s | Templates pre-loaded |

#### Diagnostic Steps

**Step 1: Check server load**

```bash
# Monitor server resource usage
top -pid $(pgrep -f HummingbirdKnowledgeServer)

# Expected:
# - CPU: < 50% for most operations
# - Memory: ~50MB base + ~10MB per connection
# - High CPU/memory indicates performance issue
```

**Step 2: Test network latency**

```bash
# Local mode (should be < 1ms)
ping localhost

# Hosted mode
ping mcp.yourdomain.com

# High latency (> 100ms) affects performance
```

**Step 3: Check timeout configuration**

Server default timeouts:
- SSE connection: 30s idle timeout
- Tool execution: 30s max execution time
- Resource retrieval: 10s max

Client timeout settings (if configurable):
- Check client documentation for timeout options
- Some clients allow custom timeout configuration

#### Solutions

**Solution 1: Increase client timeout**

If client supports timeout configuration:
- Increase for large code analysis tasks
- Keep low for simple queries to fail fast

**Solution 2: Optimize large code submissions**

For `check_architecture` or `generate_code` with large inputs:
- Split into smaller chunks
- Remove unnecessary whitespace
- Focus on specific modules/files

**Solution 3: Use hosted mode closer to client**

If using hosted mode:
- Deploy server in same region as clients
- Use CDN or edge deployment for global distribution
- Monitor network latency with `ping` or `traceroute`

**Solution 4: Check for server-side issues**

```bash
# Enable debug logging
LOG_LEVEL=debug swift run -c release HummingbirdKnowledgeServer

# Look for:
# - Slow database queries (if persistence added)
# - External API calls timing out
# - Lock contention in actor isolation
# - Memory pressure causing garbage collection pauses
```

---

## 9. Hosted Mode Specific Issues

### Problem: Hosted Mode Works Locally but Fails in Production

**Symptoms:**
- Local `http://localhost` works, `https://yourdomain.com` fails
- TLS/SSL errors
- CORS errors (not applicable to SSE)
- Reverse proxy configuration issues

#### Diagnostic Steps

**Step 1: Verify HTTPS is configured**

```bash
# Test HTTPS connection
curl -i https://mcp.yourdomain.com/health

# Expected: 200 OK with valid TLS certificate
# Common errors:
# - Certificate verification failed
# - Connection refused
# - Timeout
```

**Step 2: Check reverse proxy configuration**

If using nginx or Caddy for TLS termination:

**nginx configuration:**

```nginx
server {
    listen 443 ssl http2;
    server_name mcp.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /mcp {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        # Critical for SSE:
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;

        # Forward authentication headers
        proxy_set_header Authorization $http_authorization;
    }

    location /health {
        proxy_pass http://127.0.0.1:8080;
    }
}
```

**Caddy configuration:**

```caddyfile
mcp.yourdomain.com {
    reverse_proxy /mcp localhost:8080 {
        header_up Authorization {http.request.header.Authorization}
        flush_interval -1
    }

    reverse_proxy /health localhost:8080
}
```

**Step 3: Verify server is bound to correct interface**

```bash
# For hosted mode, bind to all interfaces
export HOST=0.0.0.0  # Not 127.0.0.1
export PORT=8080
swift run -c release HummingbirdKnowledgeServer

# Verify binding
lsof -i :8080 | grep LISTEN
# Should show 0.0.0.0:8080, not 127.0.0.1:8080
```

**Step 4: Check firewall rules**

```bash
# Verify port 8080 is accessible (if direct access, not via reverse proxy)
# On server:
sudo ufw status

# Should allow:
# - Port 443 (HTTPS)
# - Port 8080 (if direct access) or only from reverse proxy IP
```

---

## 10. Logging and Debugging

### Enabling Debug Logging

```bash
# Start server with debug logging
LOG_LEVEL=debug swift run -c release HummingbirdKnowledgeServer

# Log levels:
# - trace: Very verbose, includes all requests
# - debug: Detailed operational information
# - info: General informational messages (default)
# - notice: Normal but significant events
# - warning: Warning messages
# - error: Error messages only
# - critical: Critical errors only
```

### Useful Log Patterns

```bash
# Watch logs in real-time
LOG_LEVEL=debug swift run -c release HummingbirdKnowledgeServer 2>&1 | tee server.log

# In another terminal, grep for specific patterns:

# Connection events
grep "SSE" server.log

# Tool invocations
grep "Tool" server.log

# Authentication events
grep "Auth" server.log

# Errors only
grep "ERROR" server.log

# Performance issues (slow requests)
grep "duration" server.log | awk '$NF > 1000' # > 1 second
```

### Client-Side Debugging

**Claude Desktop:**
- Check application logs (if available in menu)
- No built-in developer console

**Cursor:**
- Help → Toggle Developer Tools
- Console tab shows MCP-related errors

**VS Code (Continue/Copilot):**
- View → Output → Select "Continue" or "GitHub Copilot"
- Shows connection status and errors

**Zed:**
- View → Developer → Debug Panel
- Shows context server connection status

---

## Summary

**Most Common Issues (90% of problems):**

1. **Server not running** → Start server before client
2. **Configuration file location wrong** → Check client-specific path
3. **Invalid JSON syntax** → Validate with `python3 -m json.tool`
4. **Client not fully restarted** → Use Cmd+Q, not just window close
5. **Port conflict** → Check `lsof -i :8080`, use different port if needed

**Quick Fix Workflow:**

```bash
# 1. Verify server is running
curl http://localhost:8080/health

# 2. Validate client config
cat <config-file> | python3 -m json.tool

# 3. Restart both server and client
# Server: Ctrl+C, then restart
# Client: Cmd+Q (full quit), then relaunch

# 4. Check logs for errors
LOG_LEVEL=debug swift run -c release HummingbirdKnowledgeServer
```

**When to Ask for Help:**

If you've tried all troubleshooting steps and the issue persists:

1. Gather diagnostic information:
   - Server version: `swift package describe`
   - Client name and version
   - Configuration file (redact tokens)
   - Server logs (last 50 lines)
   - Error messages from client

2. Use the `report_issue` tool to submit feedback
3. Check GitHub Issues: https://github.com/hummingbird-project/hummingbird-knowledge-server/issues
4. Post in Swift Forums: https://forums.swift.org/c/server

---

[← Client Compatibility](client-compatibility.md) | [Home](index.md) | [References →](references.md)
