#!/bin/bash
# Quick shell-based tests for static IP feature
# Can be run from anywhere

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0
TOTAL=0

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Test directory
TEST_DIR="/tmp/ocp4-sno-test-$$"
mkdir -p "$TEST_DIR"

echo "=========================================="
echo "Static IP Feature - Shell Tests"
echo "=========================================="
echo ""

# Function to print test result
test_result() {
    TOTAL=$((TOTAL + 1))
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASSED${NC}: $2"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ FAILED${NC}: $2"
        FAILED=$((FAILED + 1))
    fi
}

# Test 1: Check if templates exist
echo "TEST 1: Checking template files exist..."
if [ -f "$PROJECT_ROOT/templates/dnsmasq.conf.j2" ]; then
    test_result 0 "dnsmasq.conf.j2 exists"
else
    test_result 1 "dnsmasq.conf.j2 missing"
fi

# Test 2: Check if validation task exists
echo ""
echo "TEST 2: Checking validation task exists..."
if [ -f "$PROJECT_ROOT/tasks/validate_config.yaml" ]; then
    test_result 0 "validate_config.yaml exists"
else
    test_result 1 "validate_config.yaml missing"
fi

# Test 3: Check if example vars has dhcp.enabled
echo ""
echo "TEST 3: Checking example-vars.yaml has dhcp.enabled..."
if grep -q "enabled:" "$PROJECT_ROOT/example-vars.yaml"; then
    test_result 0 "dhcp.enabled parameter found in example-vars.yaml"
else
    test_result 1 "dhcp.enabled parameter missing from example-vars.yaml"
fi

# Test 4: Check dnsmasq template has conditional DHCP
echo ""
echo "TEST 4: Checking dnsmasq template has conditional DHCP..."
if grep -q "{% if dhcp.enabled" "$PROJECT_ROOT/templates/dnsmasq.conf.j2"; then
    test_result 0 "Conditional DHCP logic found in dnsmasq template"
else
    test_result 1 "Conditional DHCP logic missing from dnsmasq template"
fi

# Test 5: Check generate_grub has IP config logic
echo ""
echo "TEST 5: Checking GRUB template has IP configuration logic..."
if grep -q "ip_config" "$PROJECT_ROOT/tasks/generate_grub.yaml"; then
    test_result 0 "IP configuration logic found in generate_grub.yaml"
else
    test_result 1 "IP configuration logic missing from generate_grub.yaml"
fi

# Test 6: Check netboot has conditional tasks
echo ""
echo "TEST 6: Checking netboot has conditional DHCP/static tasks..."
if grep -q "netboot sno node with DHCP" "$PROJECT_ROOT/tasks/netboot.yaml" && \
   grep -q "netboot sno node with static IP" "$PROJECT_ROOT/tasks/netboot.yaml"; then
    test_result 0 "Conditional netboot tasks found"
else
    test_result 1 "Conditional netboot tasks missing"
fi

# Test 7: Check set_facts has conditional ports
echo ""
echo "TEST 7: Checking set_facts has conditional firewall ports..."
if grep -q "Set firewall ports with DHCP" "$PROJECT_ROOT/tasks/set_facts.yaml" && \
   grep -q "Set firewall ports without DHCP" "$PROJECT_ROOT/tasks/set_facts.yaml"; then
    test_result 0 "Conditional firewall port logic found"
else
    test_result 1 "Conditional firewall port logic missing"
fi

# Test 8: Check main.yml includes validation
echo ""
echo "TEST 8: Checking main.yml includes validation task..."
if grep -q "validate_config.yaml" "$PROJECT_ROOT/tasks/main.yml"; then
    test_result 0 "Validation task included in main.yml"
else
    test_result 1 "Validation task missing from main.yml"
fi

# Test 9: Check documentation exists
echo ""
echo "TEST 9: Checking documentation files exist..."
DOC_COUNT=0
[ -f "$PROJECT_ROOT/README.md" ] && DOC_COUNT=$((DOC_COUNT + 1))
[ -f "$PROJECT_ROOT/STATIC_IP_GUIDE.md" ] && DOC_COUNT=$((DOC_COUNT + 1))
[ -f "$PROJECT_ROOT/CHANGELOG_STATIC_IP.md" ] && DOC_COUNT=$((DOC_COUNT + 1))

if [ $DOC_COUNT -eq 3 ]; then
    test_result 0 "All documentation files exist"
else
    test_result 1 "Some documentation files missing ($DOC_COUNT/3 found)"
fi

# Test 10: Verify README has static IP section
echo ""
echo "TEST 10: Checking README has static IP documentation..."
if grep -q "Static IP Configuration" "$PROJECT_ROOT/README.md"; then
    test_result 0 "Static IP section found in README"
else
    test_result 1 "Static IP section missing from README"
fi

# Test 11: Check for backward compatibility (default value)
echo ""
echo "TEST 11: Checking templates use default(true) for backward compatibility..."
if grep -q "dhcp.enabled | default(true)" "$PROJECT_ROOT/templates/dnsmasq.conf.j2"; then
    test_result 0 "Backward compatibility default found in dnsmasq template"
else
    test_result 1 "Backward compatibility default missing from dnsmasq template"
fi

# Test 12: Verify validation has IP format check
echo ""
echo "TEST 12: Checking validation has IP format validation..."
if grep -q "regex_search.*[0-9].*[0-9].*[0-9]" "$PROJECT_ROOT/tasks/validate_config.yaml"; then
    test_result 0 "IP format validation found"
else
    test_result 1 "IP format validation missing"
fi

# Test 13: Verify validation has MAC format check
echo ""
echo "TEST 13: Checking validation has MAC format validation..."
if grep -q "regex_search.*[0-9a-fA-F].*:" "$PROJECT_ROOT/tasks/validate_config.yaml"; then
    test_result 0 "MAC format validation found"
else
    test_result 1 "MAC format validation missing"
fi

# Test 14: Check GRUB template has both DHCP and static IP logic
echo ""
echo "TEST 14: Checking GRUB has both ip=dhcp and static IP parameters..."
if grep -q "ip=dhcp" "$PROJECT_ROOT/tasks/generate_grub.yaml" && \
   grep -q "nameserver=" "$PROJECT_ROOT/tasks/generate_grub.yaml"; then
    test_result 0 "Both DHCP and static IP parameters found in GRUB"
else
    test_result 1 "Missing DHCP or static IP parameters in GRUB"
fi

# Test 15: Verify netboot removes -D flag in static mode
echo ""
echo "TEST 15: Checking netboot removes -D flag in static IP mode..."
if grep -q "lpar_netboot -i -f -t ent" "$PROJECT_ROOT/tasks/netboot.yaml"; then
    test_result 0 "Static IP netboot command (without -D) found"
else
    test_result 1 "Static IP netboot command missing"
fi

# Cleanup
rm -rf "$TEST_DIR"

# Summary
echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo "Total Tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
else
    echo -e "${GREEN}Failed: $FAILED${NC}"
fi
echo "=========================================="

# Exit with error if any tests failed
if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
fi

# Made with Bob
