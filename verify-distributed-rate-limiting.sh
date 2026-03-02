#!/usr/bin/env bash
# verify-distributed-rate-limiting.sh
#
# Verifies that distributed rate limiting works correctly across multiple server instances
# using Redis as a shared rate limit store.
#
# Test scenario:
# 1. Start Redis
# 2. Start two server instances on different ports (8081 and 8082)
# 3. Make requests to instance 1 until near the rate limit
# 4. Make a request to instance 2 from the same IP
# 5. Verify that instance 2 respects the shared rate limit state
#
# Expected result: Both instances share the same rate limit counter via Redis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
RATE_LIMIT=10  # Requests per minute
TEST_TOKEN="test-token-$(openssl rand -hex 16)"
INSTANCE1_PORT=8081
INSTANCE2_PORT=8082
REDIS_PORT=6379

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"

    # Stop server instances
    if [ -n "${INSTANCE1_PID:-}" ]; then
        kill "$INSTANCE1_PID" 2>/dev/null || true
    fi
    if [ -n "${INSTANCE2_PID:-}" ]; then
        kill "$INSTANCE2_PID" 2>/dev/null || true
    fi

    # Stop Redis container
    if [ -n "${REDIS_CONTAINER:-}" ]; then
        docker stop "$REDIS_CONTAINER" > /dev/null 2>&1 || true
        docker rm "$REDIS_CONTAINER" > /dev/null 2>&1 || true
    fi

    # Wait a bit for processes to terminate
    sleep 1

    echo -e "${GREEN}Cleanup complete${NC}"
}

trap cleanup EXIT

# Step 1: Start Redis using Docker
echo -e "${YELLOW}Step 1: Starting Redis with Docker...${NC}"
docker run -d --name redis-rate-limit-test -p "$REDIS_PORT:6379" redis:7-alpine > /dev/null 2>&1 || {
    echo -e "${RED}✗ Failed to start Redis container${NC}"
    exit 1
}
REDIS_CONTAINER="redis-rate-limit-test"
echo -e "${GREEN}✓ Redis started in Docker container${NC}"

# Wait for Redis to be ready
sleep 2
docker exec "$REDIS_CONTAINER" redis-cli ping > /dev/null || {
    echo -e "${RED}✗ Redis failed to start${NC}"
    exit 1
}

# Build the server if not already built
echo -e "${YELLOW}Building server...${NC}"
swift build > /dev/null 2>&1 || {
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
}
echo -e "${GREEN}✓ Server built${NC}"

# Step 2: Start two server instances
echo -e "${YELLOW}Step 2: Starting server instances...${NC}"

# Instance 1 on port 8081
MCP_AUTH_TOKEN="$TEST_TOKEN" \
RATE_LIMIT_PER_MINUTE="$RATE_LIMIT" \
REDIS_HOST="localhost" \
REDIS_PORT="$REDIS_PORT" \
PORT="$INSTANCE1_PORT" \
LOG_LEVEL="warning" \
./.build/debug/hummingbird-knowledge-server > instance1.log 2>&1 &
INSTANCE1_PID=$!
echo -e "${GREEN}✓ Instance 1 started on port $INSTANCE1_PORT (PID: $INSTANCE1_PID)${NC}"

# Instance 2 on port 8082
MCP_AUTH_TOKEN="$TEST_TOKEN" \
RATE_LIMIT_PER_MINUTE="$RATE_LIMIT" \
REDIS_HOST="localhost" \
REDIS_PORT="$REDIS_PORT" \
PORT="$INSTANCE2_PORT" \
LOG_LEVEL="warning" \
./.build/debug/hummingbird-knowledge-server > instance2.log 2>&1 &
INSTANCE2_PID=$!
echo -e "${GREEN}✓ Instance 2 started on port $INSTANCE2_PORT (PID: $INSTANCE2_PID)${NC}"

# Wait for servers to start
echo -e "${YELLOW}Waiting for servers to be ready...${NC}"
sleep 3

# Check if both instances are healthy
for PORT in "$INSTANCE1_PORT" "$INSTANCE2_PORT"; do
    if ! curl -sf "http://localhost:$PORT/health" > /dev/null; then
        echo -e "${RED}✗ Server on port $PORT is not responding${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ Both instances are healthy${NC}"

# Step 3: Make requests to instance 1 until near the limit
echo -e "${YELLOW}Step 3: Making $(($RATE_LIMIT - 1)) requests to instance 1...${NC}"
SUCCESS_COUNT=0
for i in $(seq 1 $(($RATE_LIMIT - 1))); do
    HTTP_CODE=$(curl -sf -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer $TEST_TOKEN" \
        "http://localhost:$INSTANCE1_PORT/health" || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        ((SUCCESS_COUNT++)) || true
    else
        echo -e "${RED}✗ Request $i failed with HTTP $HTTP_CODE${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ Successfully made $SUCCESS_COUNT requests to instance 1${NC}"

# Step 4: Make a request to instance 2 from the same IP
echo -e "${YELLOW}Step 4: Making request to instance 2 (should succeed - we're at $(($RATE_LIMIT - 1))/$RATE_LIMIT)${NC}"
HTTP_CODE=$(curl -sf -w "%{http_code}" -o /dev/null \
    -H "Authorization: Bearer $TEST_TOKEN" \
    "http://localhost:$INSTANCE2_PORT/health" || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Request to instance 2 succeeded (HTTP 200)${NC}"
else
    echo -e "${RED}✗ Request to instance 2 failed with HTTP $HTTP_CODE (expected 200)${NC}"
    exit 1
fi

# Step 5: Verify rate limit is now exhausted on both instances
echo -e "${YELLOW}Step 5: Verifying rate limit is exhausted on both instances...${NC}"

# Try instance 1 - should be rate limited
HTTP_CODE=$(curl -sf -w "%{http_code}" -o /dev/null \
    -H "Authorization: Bearer $TEST_TOKEN" \
    "http://localhost:$INSTANCE1_PORT/health" || echo "000")

if [ "$HTTP_CODE" = "429" ]; then
    echo -e "${GREEN}✓ Instance 1 correctly returns 429 (rate limited)${NC}"
else
    echo -e "${RED}✗ Instance 1 returned HTTP $HTTP_CODE (expected 429)${NC}"
    exit 1
fi

# Try instance 2 - should also be rate limited
HTTP_CODE=$(curl -sf -w "%{http_code}" -o /dev/null \
    -H "Authorization: Bearer $TEST_TOKEN" \
    "http://localhost:$INSTANCE2_PORT/health" || echo "000")

if [ "$HTTP_CODE" = "429" ]; then
    echo -e "${GREEN}✓ Instance 2 correctly returns 429 (rate limited)${NC}"
else
    echo -e "${RED}✗ Instance 2 returned HTTP $HTTP_CODE (expected 429)${NC}"
    exit 1
fi

# Verify Redis has the rate limit data
echo -e "${YELLOW}Verifying Redis state...${NC}"
KEY_COUNT=$(docker exec "$REDIS_CONTAINER" redis-cli keys "ratelimit:*" | wc -l)
if [ "$KEY_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Redis contains rate limit data ($KEY_COUNT keys)${NC}"

    # Show the rate limit entry for localhost
    LOCALHOST_KEY=$(docker exec "$REDIS_CONTAINER" redis-cli keys "ratelimit:127.0.0.1" | head -1)
    if [ -n "$LOCALHOST_KEY" ]; then
        REQUEST_COUNT=$(docker exec "$REDIS_CONTAINER" redis-cli zcard "$LOCALHOST_KEY")
        echo -e "${GREEN}✓ Localhost has $REQUEST_COUNT requests tracked in Redis${NC}"
    fi
else
    echo -e "${RED}✗ Redis does not contain any rate limit data${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ All distributed rate limiting tests passed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Summary:"
echo "  - Redis shared state works correctly"
echo "  - Both instances respect the same rate limit"
echo "  - Rate limit of $RATE_LIMIT requests per minute enforced"
echo "  - Distributed rate limiting is production-ready ✓"
echo ""
