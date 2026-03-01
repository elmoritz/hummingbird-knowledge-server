#!/bin/bash
# End-to-end verification script for dual transport support
# Tests SSE transport, HTTP transport, and both transports together

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "End-to-End Transport Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to report test result
report_result() {
    local test_name="$1"
    local result="$2"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        ((TESTS_FAILED++))
    fi
}

echo "Step 1: Build the project"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if swift build; then
    report_result "Build project" "PASS"
else
    report_result "Build project" "FAIL"
    exit 1
fi
echo ""

echo "Step 2: Run all existing tests (verify no regressions)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if swift test 2>&1 | tee /tmp/test-output.log; then
    # Extract test summary
    TEST_SUMMARY=$(grep -E "(Test Suite.*passed|failed)" /tmp/test-output.log | tail -5 || echo "Tests completed")
    echo "$TEST_SUMMARY"
    report_result "All existing tests" "PASS"
else
    report_result "All existing tests" "FAIL"
    exit 1
fi
echo ""

echo "Step 3: Verify SSE transport tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if swift test --filter MCPEndpointTests 2>&1 | tee /tmp/sse-test-output.log; then
    SSE_COUNT=$(grep -c "Test Case.*passed" /tmp/sse-test-output.log || echo "0")
    echo "SSE transport tests passed: $SSE_COUNT tests"
    report_result "SSE transport tests (MCPEndpointTests)" "PASS"
else
    report_result "SSE transport tests (MCPEndpointTests)" "FAIL"
fi
echo ""

echo "Step 4: Verify HTTP transport tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if swift test --filter HTTPTransportTests 2>&1 | tee /tmp/http-test-output.log; then
    HTTP_COUNT=$(grep -c "Test Case.*passed" /tmp/http-test-output.log || echo "0")
    echo "HTTP transport tests passed: $HTTP_COUNT tests"
    report_result "HTTP transport tests (HTTPTransportTests)" "PASS"
else
    report_result "HTTP transport tests (HTTPTransportTests)" "FAIL"
fi
echo ""

echo "Step 5: Test server startup with TRANSPORT=both"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting server with TRANSPORT=both in background..."

# Start server with both transports
TRANSPORT=both PORT=8765 swift run HummingbirdKnowledgeServer > /tmp/server-both.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
echo "Waiting for server to be ready..."
sleep 3

# Check if server is running
if kill -0 $SERVER_PID 2>/dev/null; then
    report_result "Server starts with TRANSPORT=both" "PASS"

    # Check logs for both transports being enabled
    echo "Checking server logs for transport configuration..."
    if grep -q "SSE transport enabled" /tmp/server-both.log && \
       grep -q "HTTP transport enabled" /tmp/server-both.log; then
        report_result "Both transports initialized in logs" "PASS"
        echo ""
        echo "Server log excerpt:"
        grep -E "(SSE transport|HTTP transport|MCP)" /tmp/server-both.log | head -10
    else
        report_result "Both transports initialized in logs" "FAIL"
    fi

    # Test health endpoint
    echo ""
    echo "Testing health endpoint..."
    if curl -s http://localhost:8765/health | grep -q "ok"; then
        report_result "Health endpoint responds" "PASS"
    else
        report_result "Health endpoint responds" "FAIL"
    fi

    # Test ready endpoint
    echo "Testing ready endpoint..."
    if curl -s http://localhost:8765/ready | grep -q "ok"; then
        report_result "Ready endpoint responds" "PASS"
    else
        report_result "Ready endpoint responds" "FAIL"
    fi

    # Test MCP POST endpoint (using primary transport - SSE)
    echo "Testing MCP POST endpoint..."
    JSON_REQUEST='{"jsonrpc":"2.0","method":"tools/list","id":1}'
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$JSON_REQUEST" \
        http://localhost:8765/mcp)

    if [ "$HTTP_CODE" = "202" ]; then
        report_result "MCP POST endpoint returns 202 Accepted" "PASS"
    else
        report_result "MCP POST endpoint returns 202 Accepted" "FAIL"
        echo "  Expected HTTP 202, got: $HTTP_CODE"
    fi

    # Cleanup
    echo ""
    echo "Stopping server (PID: $SERVER_PID)..."
    kill $SERVER_PID 2>/dev/null || true
    sleep 1
    kill -9 $SERVER_PID 2>/dev/null || true
else
    report_result "Server starts with TRANSPORT=both" "FAIL"
    echo "Server failed to start. Check /tmp/server-both.log for details."
    cat /tmp/server-both.log
fi
echo ""

echo "Step 6: Test server startup with TRANSPORT=sse"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TRANSPORT=sse PORT=8766 swift run HummingbirdKnowledgeServer > /tmp/server-sse.log 2>&1 &
SSE_PID=$!
sleep 2

if kill -0 $SSE_PID 2>/dev/null; then
    if grep -q "SSE transport enabled" /tmp/server-sse.log && \
       ! grep -q "HTTP transport enabled" /tmp/server-sse.log; then
        report_result "Server starts with TRANSPORT=sse only" "PASS"
    else
        report_result "Server starts with TRANSPORT=sse only" "FAIL"
    fi
    kill $SSE_PID 2>/dev/null || true
    sleep 1
    kill -9 $SSE_PID 2>/dev/null || true
else
    report_result "Server starts with TRANSPORT=sse only" "FAIL"
fi
echo ""

echo "Step 7: Test server startup with TRANSPORT=http"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TRANSPORT=http PORT=8767 swift run HummingbirdKnowledgeServer > /tmp/server-http.log 2>&1 &
HTTP_PID=$!
sleep 2

if kill -0 $HTTP_PID 2>/dev/null; then
    if grep -q "HTTP transport enabled" /tmp/server-http.log && \
       ! grep -q "SSE transport enabled" /tmp/server-http.log; then
        report_result "Server starts with TRANSPORT=http only" "PASS"
    else
        report_result "Server starts with TRANSPORT=http only" "FAIL"
    fi
    kill $HTTP_PID 2>/dev/null || true
    sleep 1
    kill -9 $HTTP_PID 2>/dev/null || true
else
    report_result "Server starts with TRANSPORT=http only" "FAIL"
fi
echo ""

# Final summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "End-to-End Verification Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}❌ E2E Verification FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}Tests Failed: 0${NC}"
    echo ""
    echo -e "${GREEN}✅ All E2E Verification Tests PASSED${NC}"
    echo ""
    echo "Both transports are working correctly:"
    echo "  • SSE transport: ✓ Tests passing, server runs with TRANSPORT=sse"
    echo "  • HTTP transport: ✓ Tests passing, server runs with TRANSPORT=http"
    echo "  • Both together: ✓ Server runs with TRANSPORT=both"
    echo ""
    echo "The implementation successfully supports:"
    echo "  1. SSE transport for streaming responses"
    echo "  2. HTTP transport for request/response pairs"
    echo "  3. Simultaneous operation of both transports"
    echo "  4. Configuration via TRANSPORT environment variable"
fi

# Cleanup
rm -f /tmp/server-*.log /tmp/test-output.log /tmp/sse-test-output.log /tmp/http-test-output.log

exit 0
