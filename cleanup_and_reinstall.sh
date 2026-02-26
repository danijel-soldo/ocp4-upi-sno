#!/bin/bash
#
# OpenShift SNO Cleanup and Reinstall Script
# This script cleans up a failed installation and prepares for a fresh reinstall
#
# Usage: ./cleanup_and_reinstall.sh [options]
#   Options:
#     --force-download    Force re-download of RHCOS and OCP files
#     --keep-downloads    Keep existing downloads (faster reinstall)
#     --help             Show this help message
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
FORCE_DOWNLOAD=false
VARS_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force-download)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --keep-downloads)
            FORCE_DOWNLOAD=false
            shift
            ;;
        --vars-file)
            VARS_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --force-download    Force re-download of RHCOS and OCP files"
            echo "  --keep-downloads    Keep existing downloads (default, faster)"
            echo "  --vars-file FILE    Specify vars file (default: my-vars.yaml)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Set default vars file if not specified
if [ -z "$VARS_FILE" ]; then
    if [ -f "my-vars.yaml" ]; then
        VARS_FILE="my-vars.yaml"
    else
        echo -e "${RED}Error: my-vars.yaml not found. Please create it from example-vars.yaml${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift SNO Cleanup and Reinstall${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Extract HMC and LPAR info from vars file
echo -e "${YELLOW}Reading configuration from $VARS_FILE...${NC}"
if ! [ -f "$VARS_FILE" ]; then
    echo -e "${RED}Error: Configuration file $VARS_FILE not found${NC}"
    exit 1
fi

# Parse YAML to get HMC and LPAR details
PVM_HMC=$(grep "^pvm_hmc:" "$VARS_FILE" | awk '{print $2}')
PVMCEC=$(grep "pvmcec:" "$VARS_FILE" | grep -v "day2" | head -1 | awk '{print $2}')
PVMLPAR=$(grep "pvmlpar:" "$VARS_FILE" | grep -v "day2" | head -1 | awk '{print $2}')

if [ -z "$PVM_HMC" ] || [ -z "$PVMCEC" ] || [ -z "$PVMLPAR" ]; then
    echo -e "${RED}Error: Could not parse HMC/LPAR information from $VARS_FILE${NC}"
    echo "Please ensure pvm_hmc, sno.pvmcec, and sno.pvmlpar are set correctly"
    exit 1
fi

echo -e "${GREEN}Configuration loaded:${NC}"
echo "  HMC: $PVM_HMC"
echo "  CEC: $PVMCEC"
echo "  LPAR: $PVMLPAR"
echo ""

# Step 1: Stop any running openshift-install processes
echo -e "${YELLOW}Step 1: Stopping openshift-install processes...${NC}"
if pgrep -f openshift-install > /dev/null; then
    echo "  Killing openshift-install processes..."
    pkill -9 -f openshift-install || true
    sleep 2
    echo -e "${GREEN}  ✓ Processes stopped${NC}"
else
    echo -e "${GREEN}  ✓ No openshift-install processes running${NC}"
fi
echo ""

# Step 2: Clean up work directory
echo -e "${YELLOW}Step 2: Cleaning up work directory...${NC}"
WORKDIR=$(grep "^workdir:" "$VARS_FILE" | awk '{print $2}' | sed 's/"//g')
if [ -z "$WORKDIR" ]; then
    WORKDIR="~/ocp4-sno"
fi
WORKDIR=$(eval echo "$WORKDIR")  # Expand ~ to home directory

if [ -d "$WORKDIR" ]; then
    echo "  Removing $WORKDIR..."
    rm -rf "$WORKDIR"
    echo -e "${GREEN}  ✓ Work directory cleaned${NC}"
else
    echo -e "${GREEN}  ✓ Work directory doesn't exist${NC}"
fi
echo ""

# Step 3: Power off SNO LPAR
echo -e "${YELLOW}Step 3: Powering off SNO LPAR...${NC}"
echo "  Connecting to HMC: $PVM_HMC"
echo "  Shutting down LPAR: $PVMLPAR on CEC: $PVMCEC"

if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$PVM_HMC" "lssyscfg -r lpar -m $PVMCEC --filter lpar_names=$PVMLPAR" > /dev/null 2>&1; then
    # Check current state
    LPAR_STATE=$(ssh -o StrictHostKeyChecking=no "$PVM_HMC" "lssyscfg -r lpar -m $PVMCEC --filter lpar_names=$PVMLPAR -F state" 2>/dev/null || echo "Unknown")
    echo "  Current LPAR state: $LPAR_STATE"
    
    if [ "$LPAR_STATE" != "Not Activated" ]; then
        echo "  Issuing shutdown command..."
        ssh -o StrictHostKeyChecking=no "$PVM_HMC" "chsysstate -r lpar -m $PVMCEC -o shutdown --immed -n $PVMLPAR" 2>/dev/null || true
        sleep 5
        echo -e "${GREEN}  ✓ LPAR shutdown initiated${NC}"
    else
        echo -e "${GREEN}  ✓ LPAR already powered off${NC}"
    fi
else
    echo -e "${RED}  ✗ Could not connect to HMC or LPAR not found${NC}"
    echo "  Please manually power off the LPAR before continuing"
    read -p "Press Enter when LPAR is powered off..."
fi
echo ""

# Step 4: Optional - Force re-download of files
if [ "$FORCE_DOWNLOAD" = true ]; then
    echo -e "${YELLOW}Step 4: Forcing re-download of RHCOS and OCP files...${NC}"
    echo "  Removing cached downloads..."
    sudo rm -rf /usr/local/src/rhcos-* 2>/dev/null || true
    sudo rm -rf /usr/local/src/openshift-* 2>/dev/null || true
    sudo rm -rf /var/lib/tftpboot/rhcos/* 2>/dev/null || true
    sudo rm -rf /var/www/html/install/* 2>/dev/null || true
    echo -e "${GREEN}  ✓ Cached files removed${NC}"
else
    echo -e "${YELLOW}Step 4: Keeping existing downloads (use --force-download to re-download)${NC}"
    echo -e "${GREEN}  ✓ Existing downloads will be reused${NC}"
fi
echo ""

# Step 5: Wait for LPAR to fully power off
echo -e "${YELLOW}Step 5: Waiting for LPAR to fully power off...${NC}"
echo "  Waiting 30 seconds..."
sleep 30
echo -e "${GREEN}  ✓ Wait complete${NC}"
echo ""

# Step 6: Ready to reinstall
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Verify your configuration in $VARS_FILE"
echo "   - Check OpenShift version (rhcos_rhcos_base, ocp_client_tag)"
echo "   - Ensure versions are compatible (e.g., both 4.14)"
echo ""
echo "2. Run the installation:"
echo -e "   ${GREEN}ansible-playbook tasks/main.yml -e @$VARS_FILE${NC}"
echo ""
echo -e "${YELLOW}Recommended versions for ppc64le:${NC}"
echo "  - OpenShift 4.14 (stable, tested)"
echo "  - OpenShift 4.13 (very stable)"
echo ""
echo "Example configuration:"
echo "  rhcos_rhcos_base: \"4.14\""
echo "  rhcos_rhcos_tag: \"latest\""
echo "  ocp_client_tag: \"latest-4.14\""
echo ""

# Made with Bob
