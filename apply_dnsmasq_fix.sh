#!/bin/bash
#
# dnsmasq Port Binding Fix Script
# Applies fixes for dnsmasq port binding issues
# Run diagnose_dnsmasq_ports.sh first to identify issues
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Don't exit on errors
set +e

print_header() {
    echo -e "\n${BLUE}=========================================="
    echo "$1"
    echo -e "==========================================${NC}\n"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Usage: sudo $0 [vars-file.yaml]"
    exit 1
fi

# Load helper IP from vars file
VARS_FILE="${1:-my-vars.yaml}"
if [ -f "$VARS_FILE" ]; then
    # Helper IP is the DNS server IP (dhcp.dns), not the router/gateway
    HELPER_IP=$(grep -A10 "^dhcp:" "$VARS_FILE" | grep "dns:" | awk '{print $2}' | tr -d '"')
    # If dns is not set, calculate from SNO IP
    if [ -z "$HELPER_IP" ]; then
        SNO_IP=$(grep -A5 "^sno:" "$VARS_FILE" | grep "ipaddr:" | awk '{print $2}' | tr -d '"')
        if [ -n "$SNO_IP" ]; then
            BASE_IP=$(echo "$SNO_IP" | cut -d. -f1-3)
            LAST_OCTET=$(echo "$SNO_IP" | cut -d. -f4)
            HELPER_LAST=$((LAST_OCTET - 1))
            HELPER_IP="${BASE_IP}.${HELPER_LAST}"
        fi
    fi
fi

# Default if still not found
if [ -z "$HELPER_IP" ]; then
    HELPER_IP="129.40.98.129"
fi

print_header "dnsmasq Port Binding Fix"
print_info "Helper IP: $HELPER_IP"
print_warn "This script will modify /etc/dnsmasq.conf and restart dnsmasq"

# Find correct interface with helper IP
print_info "Finding interface with helper IP..."
CORRECT_IFACE=$(ip addr show | grep -B2 "$HELPER_IP" | head -1 | awk '{print $2}' | tr -d ':')

if [ -z "$CORRECT_IFACE" ]; then
    print_fail "Helper IP $HELPER_IP not found on any interface!"
    print_info "Available interfaces:"
    ip addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'
    echo ""
    print_fail "Cannot proceed - helper IP must be assigned to an interface first"
    exit 1
fi

print_pass "Helper IP found on interface: $CORRECT_IFACE"

# Get currently configured interface
CONFIGURED_IFACE=$(grep "^interface=" /etc/dnsmasq.conf 2>/dev/null | cut -d= -f2)

if [ -n "$CONFIGURED_IFACE" ]; then
    print_info "Currently configured interface: $CONFIGURED_IFACE"
else
    print_info "No interface currently configured in dnsmasq.conf"
fi

# ==========================================
# Apply Fixes
# ==========================================
print_header "Applying Fixes"

CHANGES_MADE=false

# Fix 1: Update interface if wrong or missing
if [ -z "$CONFIGURED_IFACE" ] || [ "$CONFIGURED_IFACE" != "$CORRECT_IFACE" ]; then
    print_info "Updating interface configuration..."
    
    # Backup config
    BACKUP_FILE="/etc/dnsmasq.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/dnsmasq.conf "$BACKUP_FILE"
    print_info "Backup created: $BACKUP_FILE"
    
    # Update or add interface line
    if [ -n "$CONFIGURED_IFACE" ]; then
        sed -i "s/^interface=.*/interface=$CORRECT_IFACE/" /etc/dnsmasq.conf
        print_pass "Updated interface from '$CONFIGURED_IFACE' to '$CORRECT_IFACE'"
    else
        # Add interface line after domain line
        sed -i "/^domain=/a interface=$CORRECT_IFACE" /etc/dnsmasq.conf
        print_pass "Added interface=$CORRECT_IFACE to configuration"
    fi
    
    CHANGES_MADE=true
fi

# Fix 2: Ensure interface is UP
if ! ip link show "$CORRECT_IFACE" | grep -q "state UP"; then
    print_info "Bringing interface UP..."
    ip link set "$CORRECT_IFACE" up
    sleep 1
    
    if ip link show "$CORRECT_IFACE" | grep -q "state UP"; then
        print_pass "Interface $CORRECT_IFACE is now UP"
        CHANGES_MADE=true
    else
        print_fail "Failed to bring interface UP"
    fi
fi

# Fix 3: Restart dnsmasq
if [ "$CHANGES_MADE" = true ] || ! systemctl is-active --quiet dnsmasq; then
    print_info "Restarting dnsmasq service..."
    systemctl restart dnsmasq
    sleep 2
    
    if systemctl is-active --quiet dnsmasq; then
        print_pass "dnsmasq restarted successfully"
    else
        print_fail "dnsmasq failed to start"
        print_info "Check logs: journalctl -u dnsmasq -n 20"
        exit 1
    fi
else
    print_info "No changes needed - dnsmasq is already configured correctly"
fi

# ==========================================
# Verify Fix
# ==========================================
print_header "Verifying Fix"

sleep 2

VERIFICATION_PASSED=true

# Check if dnsmasq is running
if systemctl is-active --quiet dnsmasq; then
    print_pass "dnsmasq service is running"
else
    print_fail "dnsmasq service is NOT running"
    VERIFICATION_PASSED=false
fi

# Check ports
if lsof -i :53 2>/dev/null | grep -q dnsmasq; then
    print_pass "dnsmasq listening on port 53 (DNS)"
else
    print_fail "dnsmasq NOT listening on port 53"
    VERIFICATION_PASSED=false
fi

if lsof -i :67 2>/dev/null | grep -q dnsmasq; then
    print_pass "dnsmasq listening on port 67 (DHCP) ✓"
else
    print_fail "dnsmasq NOT listening on port 67"
    VERIFICATION_PASSED=false
fi

if lsof -i :69 2>/dev/null | grep -q dnsmasq; then
    print_pass "dnsmasq listening on port 69 (TFTP)"
else
    print_fail "dnsmasq NOT listening on port 69"
    VERIFICATION_PASSED=false
fi

# ==========================================
# Summary
# ==========================================
print_header "Summary"

if [ "$VERIFICATION_PASSED" = true ]; then
    echo -e "${GREEN}=========================================="
    echo "✓ FIX SUCCESSFUL"
    echo "==========================================${NC}"
    echo ""
    echo "dnsmasq is now listening on all required ports:"
    echo "  • Port 53 (DNS)"
    echo "  • Port 67 (DHCP/BOOTP)"
    echo "  • Port 69 (TFTP)"
    echo ""
    echo "You can now proceed with LPAR netboot."
    echo ""
    echo "Verify with:"
    echo "  sudo netstat -tulpn | grep dnsmasq"
    echo ""
    echo "Monitor BOOTP requests:"
    echo "  sudo journalctl -u dnsmasq -f"
    exit 0
else
    echo -e "${RED}=========================================="
    echo "✗ FIX INCOMPLETE"
    echo "==========================================${NC}"
    echo ""
    echo "dnsmasq is still not listening on all required ports."
    echo ""
    echo "Additional troubleshooting:"
    echo "  1. Check logs: sudo journalctl -u dnsmasq -n 50"
    echo "  2. Test config: sudo dnsmasq --test"
    echo "  3. Check conflicts: sudo lsof -i :67"
    echo "  4. Manual start: sudo dnsmasq --no-daemon --log-queries"
    echo ""
    echo "Run diagnostics again:"
    echo "  sudo ./diagnose_dnsmasq_ports.sh $VARS_FILE"
    exit 1
fi

# Made with Bob
