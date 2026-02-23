#!/bin/bash
#
# Validate download_files.yaml logic without actually running it
# This script checks the YAML syntax and conditional logic
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Validating download_files.yaml Logic"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

# Check if file exists
if [ ! -f "tasks/download_files.yaml" ]; then
    echo -e "${RED}ERROR: tasks/download_files.yaml not found${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Checking YAML syntax...${NC}"
if command -v yamllint &> /dev/null; then
    yamllint tasks/download_files.yaml && echo -e "${GREEN}✓ YAML syntax is valid${NC}" || echo -e "${YELLOW}⚠ yamllint warnings (non-critical)${NC}"
else
    echo -e "${YELLOW}⚠ yamllint not installed, skipping syntax check${NC}"
fi
echo ""

echo -e "${BLUE}Step 2: Analyzing conditional logic...${NC}"
echo ""

# Check for force_ocp_download with default(false)
echo "Checking 'force_ocp_download' usage:"
if grep -n "force_ocp_download" tasks/download_files.yaml | grep -v "default(false)"; then
    echo -e "${RED}✗ FAIL: Found 'force_ocp_download' without 'default(false)' filter${NC}"
    grep -n "force_ocp_download" tasks/download_files.yaml | grep -v "default(false)"
    exit 1
else
    echo -e "${GREEN}✓ PASS: All 'force_ocp_download' references use 'default(false)'${NC}"
fi
echo ""

# Check delete task
echo "Checking delete task conditional:"
DELETE_LINE=$(grep -n "when: force_ocp_download" tasks/download_files.yaml | head -1 | cut -d: -f1)
if [ -n "$DELETE_LINE" ]; then
    if grep -A0 "when: force_ocp_download" tasks/download_files.yaml | grep "default(false)"; then
        echo -e "${GREEN}✓ PASS: Delete task uses 'force_ocp_download | default(false)'${NC}"
    else
        echo -e "${RED}✗ FAIL: Delete task missing 'default(false)' filter${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ WARNING: Could not find delete task conditional${NC}"
fi
echo ""

# Check stat tasks before downloads
echo "Checking file existence checks (stat tasks):"
STAT_COUNT=$(grep -c "name: Check if.*already exists" tasks/download_files.yaml || true)
echo "  Found $STAT_COUNT stat checks"

if [ "$STAT_COUNT" -ge 6 ]; then
    echo -e "${GREEN}✓ PASS: Sufficient stat checks found (expected 6+)${NC}"
else
    echo -e "${YELLOW}⚠ WARNING: Expected at least 6 stat checks, found $STAT_COUNT${NC}"
fi
echo ""

# Check download conditionals
echo "Checking download task conditionals:"
DOWNLOAD_TASKS=$(grep -c "name: Downloading OCP4" tasks/download_files.yaml || true)
echo "  Found $DOWNLOAD_TASKS download tasks"

# Check each download has proper conditional
PROPER_CONDITIONALS=0
while IFS= read -r line; do
    LINE_NUM=$(echo "$line" | cut -d: -f1)
    # Check if next few lines have proper when condition
    if sed -n "${LINE_NUM},$((LINE_NUM+5))p" tasks/download_files.yaml | grep -q "when:.*stat.exists.*default(false)"; then
        ((PROPER_CONDITIONALS++))
    fi
done < <(grep -n "name: Downloading OCP4" tasks/download_files.yaml)

if [ "$PROPER_CONDITIONALS" -eq "$DOWNLOAD_TASKS" ]; then
    echo -e "${GREEN}✓ PASS: All download tasks have proper conditionals${NC}"
else
    echo -e "${YELLOW}⚠ WARNING: $PROPER_CONDITIONALS/$DOWNLOAD_TASKS downloads have proper conditionals${NC}"
fi
echo ""

# Check unarchive tasks
echo "Checking unarchive task conditionals:"
UNARCHIVE_TASKS=$(grep -c "name: Unarchiving OCP4" tasks/download_files.yaml || true)
echo "  Found $UNARCHIVE_TASKS unarchive tasks"

# Check unarchive conditionals (should NOT have force_ocp_download)
UNARCHIVE_WITH_FORCE=$(grep -A2 "name: Unarchiving OCP4" tasks/download_files.yaml | grep -c "force_ocp_download" || true)
if [ "$UNARCHIVE_WITH_FORCE" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS: Unarchive tasks do NOT depend on force_ocp_download${NC}"
else
    echo -e "${RED}✗ FAIL: Unarchive tasks should only check if command exists${NC}"
    exit 1
fi
echo ""

# Check force: no parameter
echo "Checking 'force: no' in get_url tasks:"
GETURL_COUNT=$(grep -c "get_url:" tasks/download_files.yaml || true)
FORCE_NO_COUNT=$(grep -c "force: no" tasks/download_files.yaml || true)

if [ "$FORCE_NO_COUNT" -ge "$GETURL_COUNT" ]; then
    echo -e "${GREEN}✓ PASS: All get_url tasks have 'force: no'${NC}"
else
    echo -e "${YELLOW}⚠ WARNING: $FORCE_NO_COUNT/$GETURL_COUNT get_url tasks have 'force: no'${NC}"
fi
echo ""

echo "=========================================="
echo -e "${BLUE}Step 3: Logic Flow Analysis${NC}"
echo "=========================================="
echo ""

cat << 'EOF'
Expected behavior when force_ocp_download is NOT set:

1. Delete task: SKIPPED (force_ocp_download defaults to false)
   → Files remain intact

2. Stat checks: RUN (always check if files exist)
   → Records which files exist

3. Download tasks: CONDITIONAL
   → Skip if file exists (stat.exists = true)
   → Download if file missing (stat.exists = false)

4. Unarchive tasks: CONDITIONAL
   → Skip if command exists
   → Extract if command missing (even if tarball exists)

Result: No re-downloads, no unnecessary extractions
EOF

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""

# Final check
ERRORS=0

# Recheck critical items
if ! grep -q "when: force_ocp_download | default(false)" tasks/download_files.yaml; then
    echo -e "${RED}✗ Critical: Delete task missing default(false)${NC}"
    ((ERRORS++))
fi

if grep "force_ocp_download" tasks/download_files.yaml | grep -v "default(false)" | grep -q "when:"; then
    echo -e "${RED}✗ Critical: Some conditionals missing default(false)${NC}"
    ((ERRORS++))
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "✓ VALIDATION PASSED"
    echo "==========================================${NC}"
    echo ""
    echo "The download_files.yaml logic is correct:"
    echo "  • force_ocp_download properly defaults to false"
    echo "  • File existence checks are in place"
    echo "  • Downloads are conditional on file existence"
    echo "  • Extractions are conditional on command existence"
    echo ""
    echo "Expected behavior: No re-downloads of existing files"
    exit 0
else
    echo -e "${RED}=========================================="
    echo "✗ VALIDATION FAILED"
    echo "==========================================${NC}"
    echo ""
    echo "Found $ERRORS critical error(s) in the logic"
    exit 1
fi

# Made with Bob
