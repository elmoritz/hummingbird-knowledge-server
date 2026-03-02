# Distributed Rate Limiting Verification Guide

This document describes how to verify that distributed rate limiting works correctly across multiple server instances using Redis as a shared state store.

## Overview

The distributed rate limiting implementation uses Redis sorted sets to track request timestamps in a sliding 60-second window. This enables accurate rate limiting across multiple server instances, which is essential for load-balanced deployments.

## Implementation Details

- **Store**: `RedisRateLimitStore` (Sources/HummingbirdKnowledgeServer/RateLimit/RedisRateLimitStore.swift)
- **Redis Data Structure**: Sorted sets with key pattern `ratelimit:<client-ip>`
- **Window**: 60-second sliding window
- **Cleanup**: Automatic expiration after 120 seconds of inactivity

## Verification Steps

### Prerequisites

1. Redis server running and accessible
2. Swift application built: `swift build`
3. `curl` for making HTTP requests
4. Authentication token for hosted mode

### Method 1: Automated Verification (Recommended)

Use the provided verification script when Docker is available:

```bash
./verify-distributed-rate-limiting.sh
```

This script:
1. Starts a Redis instance in Docker
2. Launches two server instances on ports 8081 and 8082
3. Makes requests to both instances to verify shared rate limit state
4. Confirms that rate limits are synchronized via Redis
5. Cleans up all resources

**Expected Result**: All tests pass, confirming that both instances share the same rate limit counter.

### Method 2: Manual Verification

#### Step 1: Start Redis

```bash
# Using Docker
docker run -d --name redis-test -p 6379:6379 redis:7-alpine

# Or using local Redis installation
redis-server --port 6379
```

#### Step 2: Start Two Server Instances

Terminal 1 (Instance 1 on port 8081):
```bash
MCP_AUTH_TOKEN="test-token-123" \
RATE_LIMIT_PER_MINUTE="10" \
REDIS_HOST="localhost" \
REDIS_PORT="6379" \
PORT="8081" \
LOG_LEVEL="info" \
./.build/debug/hummingbird-knowledge-server
```

Terminal 2 (Instance 2 on port 8082):
```bash
MCP_AUTH_TOKEN="test-token-123" \
RATE_LIMIT_PER_MINUTE="10" \
REDIS_HOST="localhost" \
REDIS_PORT="6379" \
PORT="8082" \
LOG_LEVEL="info" \
./.build/debug/hummingbird-knowledge-server
```

#### Step 3: Make Requests to Instance 1

Make 9 requests (rate limit is 10/minute):

```bash
for i in {1..9}; do
  curl -H "Authorization: Bearer test-token-123" http://localhost:8081/health
  echo " - Request $i to instance 1"
done
```

**Expected**: All 9 requests succeed (HTTP 200)

#### Step 4: Make Request to Instance 2

```bash
curl -v -H "Authorization: Bearer test-token-123" http://localhost:8082/health
```

**Expected**: Request succeeds (HTTP 200) because we're at 10/10 requests

#### Step 5: Verify Rate Limit is Exhausted

Try one more request to either instance:

```bash
curl -v -H "Authorization: Bearer test-token-123" http://localhost:8081/health
```

**Expected**: Request is rate limited (HTTP 429)

Also verify on instance 2:

```bash
curl -v -H "Authorization: Bearer test-token-123" http://localhost:8082/health
```

**Expected**: Also rate limited (HTTP 429)

#### Step 6: Verify Redis State

Check that Redis contains the rate limit data:

```bash
# List all rate limit keys
redis-cli keys "ratelimit:*"

# Check the count for localhost
redis-cli zcard "ratelimit:127.0.0.1"
```

**Expected**:
- One or more `ratelimit:*` keys exist
- The count matches the number of requests made (10)

### Method 3: Docker Compose Verification

Use the provided Docker Compose setup:

```bash
# Start the hosted profile with Redis
docker compose --profile hosted up -d

# Scale the application to 2 instances
docker compose --profile hosted up -d --scale hummingbird-knowledge-hosted=2

# Follow the manual verification steps above, using the load balancer endpoint
```

## Success Criteria

✅ **Pass**: Both instances share the same rate limit counter
- Requests to instance 1 count towards the global limit
- Requests to instance 2 see the same limit state
- Rate limit exhaustion affects both instances simultaneously
- Redis contains the rate limit data in sorted sets

❌ **Fail**: Instances have independent rate limits
- Each instance tracks its own counter
- Rate limit on instance 1 doesn't affect instance 2
- Redis doesn't contain rate limit data

## Troubleshooting

### Redis Connection Errors

If you see "Redis errors" in the logs:

1. Verify Redis is running: `redis-cli ping`
2. Check Redis host/port in environment variables
3. Ensure firewall allows connections to Redis port

### Rate Limit Not Shared

If rate limits appear independent:

1. Verify both instances use the same Redis instance
2. Check that `REDIS_HOST` and `REDIS_PORT` are set correctly
3. Ensure both instances are in hosted mode (`MCP_AUTH_TOKEN` is set)
4. Verify Redis connection is successful in startup logs

### In-Memory Fallback

If you see "In-memory rate limit store initialized":

1. This means Redis is not configured
2. Set `REDIS_HOST` and `REDIS_PORT` environment variables
3. Ensure you're in hosted mode (`MCP_AUTH_TOKEN` is set)

## Architecture Notes

### Why Redis?

- **Shared State**: Multiple instances can access the same data
- **Atomic Operations**: `ZADD`, `ZCARD`, and `ZREMRANGEBYSCORE` are atomic
- **Automatic Cleanup**: `EXPIRE` prevents unbounded memory growth
- **High Performance**: Sub-millisecond latency for rate limit checks

### Sliding Window Implementation

The implementation uses Redis sorted sets where:
- **Key**: `ratelimit:<client-ip>`
- **Members**: Unique timestamps with microsecond precision
- **Scores**: Unix timestamps (seconds since epoch)

On each request:
1. Remove entries older than 60 seconds
2. Count remaining entries
3. If count < limit, add new entry with current timestamp
4. Set expiration to 2 minutes for automatic cleanup

This provides accurate rate limiting with a true sliding window (not fixed buckets).

### Fail-Closed Behavior

On Redis errors, the implementation fails closed (rejects requests) to protect the system. In production, these errors should be monitored via alerts.

## Production Deployment

For production deployments:

1. **High Availability**: Use Redis Sentinel or Redis Cluster
2. **Monitoring**: Track Redis connection errors via metrics/alerts
3. **Backup**: Use in-memory fallback for Redis outages (single instance mode)
4. **Security**: Use Redis AUTH and TLS for production

## Related Files

- Implementation: `Sources/HummingbirdKnowledgeServer/RateLimit/RedisRateLimitStore.swift`
- Configuration: `Sources/HummingbirdKnowledgeServer/Configuration/AppConfiguration.swift`
- Middleware: `Sources/HummingbirdKnowledgeServer/Middleware/RateLimitMiddleware.swift`
- Docker Compose: `docker-compose.yml`
- Environment Example: `.env.example`
