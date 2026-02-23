#!/bin/bash
#
# Test script to verify that download_files.yaml does NOT re-download existing files
# This script checks file timestamps before and after running the playbook
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Testing Download Skip Functionality"
echo "=========================================="
echo ""

# Define files to check
declare -A FILES=(
    ["/usr/local/src/openshift-client-linux.tar.gz"]="OCP Client Tarball"
    ["/usr/local/src/openshift-install-linux.tar.gz"]="OCP Installer Tarball"
    ["/usr/local/bin/oc"]="oc command"
    ["/usr/local/bin/openshift-install"]="openshift-install command"
    ["/var/lib/tftpboot/rhcos/initramfs.img"]="RHCOS initramfs"
    ["/var/lib/tftpboot/rhcos/kernel"]="RHCOS kernel"
    ["/var/www/html/install/rootfs.img"]="RHCOS rootfs"
)

# Find RHCOS ISO dynamically
RHCOS_ISO=$(ls /usr/local/src/rhcos-live-*.iso 2>/dev/null | head -1)
if [ -n "$RHCOS_ISO" ]; then
    FILES["$RHCOS_ISO"]="RHCOS ISO"
fi

# Store timestamps before running playbook
declare -A TIMESTAMPS_BEFORE
declare -A TIMESTAMPS_AFTER

echo "Step 1: Recording file timestamps BEFORE playbook run..."
echo ""

for file in "${!FILES[@]}"; do
    if [ -f "$file" ]; then
        TIMESTAMPS_BEFORE["$file"]=$(stat -f "%m" "$file" 2>/dev/null || stat -c "%Y" "$file" 2>/dev/null)
        echo "  ✓ ${FILES[$file]}: $(ls -lh "$file" | awk '{print $5, $6, $7, $8}')"
    else
        echo "  ✗ ${FILES[$file]}: NOT FOUND (will be downloaded)"
        TIMESTAMPS_BEFORE["$file"]="missing"
    fi
done

echo ""
echo "Step 2: Running playbook (download_files tasks only)..."
echo ""

# Create a minimal test playbook that only runs download_files
cat > /tmp/test_download_only.yml << 'EOF'
---
- name: Test Download Files
  hosts: localhost
  gather_facts: yes
  vars_files:
    - "{{ lookup('env', 'VARS_FILE') }}"
  tasks:
    - name: Include download_files tasks
      include_tasks: tasks/download_files.yaml
EOF

# Run the playbook
cd "$(dirname "$0")"
VARS_FILE="${1:-my-vars.yaml}"

if [ ! -f "$VARS_FILE" ]; then
    echo -e "${RED}ERROR: Variables file '$VARS_FILE' not found${NC}"
    echo "Usage: $0 [vars-file.yaml]"
    exit 1
fi

echo "Using variables file: $VARS_FILE"
echo ""

# Run playbook and capture output
VARS_FILE="$PWD/$VARS_FILE" ansible-playbook /tmp/test_download_only.yml 2>&1 | tee /tmp/playbook_output.log

echo ""
echo "Step 3: Recording file timestamps AFTER playbook run..."
echo ""

for file in "${!FILES[@]}"; do
    if [ -f "$file" ]; then
        TIMESTAMPS_AFTER["$file"]=$(stat -f "%m" "$file" 2>/dev/null || stat -c "%Y" "$file" 2>/dev/null)
        echo "  ✓ ${FILES[$file]}: $(ls -lh "$file" | awk '{print $5, $6, $7, $8}')"
    else
        echo "  ✗ ${FILES[$file]}: STILL NOT FOUND"
        TIMESTAMPS_AFTER["$file"]="missing"
    fi
done

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo ""

# Compare timestamps
CHANGED=0
UNCHANGED=0
CREATED=0

for file in "${!FILES[@]}"; do
    before="${TIMESTAMPS_BEFORE[$file]}"
    after="${TIMESTAMPS_AFTER[$file]}"
    
    if [ "$before" = "missing" ] && [ "$after" != "missing" ]; then
        echo -e "${GREEN}✓ CREATED:${NC} ${FILES[$file]}"
        ((CREATED++))
    elif [ "$before" != "missing" ] && [ "$after" = "missing" ]; then
        echo -e "${RED}✗ DELETED:${NC} ${FILES[$file]}"
        ((CHANGED++))
    elif [ "$before" = "$after" ]; then
        echo -e "${GREEN}✓ UNCHANGED:${NC} ${FILES[$file]} (timestamp: $after)"
        ((UNCHANGED++))
    else
        echo -e "${RED}✗ MODIFIED:${NC} ${FILES[$file]} (before: $before, after: $after)"
        ((CHANGED++))
    fi
done

echo ""
echo "Summary:"
echo "  - Files unchanged: $UNCHANGED"
echo "  - Files created: $CREATED"
echo "  - Files modified/deleted: $CHANGED"
echo ""

# Check playbook output for download tasks
echo "Checking playbook output for download activity..."
echo ""

if grep -q "Downloading OCP4" /tmp/playbook_output.log; then
    DOWNLOAD_TASKS=$(grep "Downloading OCP4" /tmp/playbook_output.log | wc -l)
    SKIPPED_TASKS=$(grep -A1 "Downloading OCP4" /tmp/playbook_output.log | grep "skipping:" | wc -l)
    
    echo "  - Download tasks found: $DOWNLOAD_TASKS"
    echo "  - Download tasks skipped: $SKIPPED_TASKS"
    
    if [ "$SKIPPED_TASKS" -eq "$DOWNLOAD_TASKS" ]; then
        echo -e "  ${GREEN}✓ All download tasks were skipped${NC}"
    else
        echo -e "  ${YELLOW}⚠ Some download tasks were executed${NC}"
    fi
fi

echo ""

# Final verdict
if [ $CHANGED -eq 0 ] && [ $UNCHANGED -gt 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "TEST PASSED ✓"
    echo "==========================================${NC}"
    echo "No existing files were re-downloaded or modified."
    exit 0
elif [ $CREATED -gt 0 ] && [ $CHANGED -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "TEST PASSED ✓"
    echo "==========================================${NC}"
    echo "Missing files were created, existing files were not modified."
    exit 0
else
    echo -e "${RED}=========================================="
    echo "TEST FAILED ✗"
    echo "==========================================${NC}"
    echo "Some existing files were modified or deleted!"
    exit 1
fi

# Made with Bob
