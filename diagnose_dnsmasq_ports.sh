#!/bin/bash
#
# dnsmasq Port Binding Diagnostic Script (Read-Only)
# Diagnoses why dnsmasq is not listening on required ports
# Does NOT make any changes - only reports issues
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

print_header "dnsmasq Port Binding Diagnostic (Read-Only)"
print_info "Helper IP: $HELPER_IP"
print_info "This script will NOT make any changes"

# Track issues found
ISSUES_FOUND=0

# ==========================================
# 1. Check dnsmasq Service Status
# ==========================================
print_header "1. dnsmasq Service Status"

if systemctl is-active --quiet dnsmasq; then
    print_pass "dnsmasq service is running"
    DNSMASQ_PID=$(pgrep dnsmasq)
    print_info "dnsmasq PID: $DNSMASQ_PID"
else
    print_fail "dnsmasq service is NOT running"
    print_info "Fix: sudo systemctl start dnsmasq"
    ((ISSUES_FOUND++))
fi

if systemctl is-enabled --quiet dnsmasq; then
    print_pass "dnsmasq service is enabled"
else
    print_warn "dnsmasq service is not enabled (won't start on boot)"
    print_info "Fix: sudo systemctl enable dnsmasq"
fi

# ==========================================
# 2. Check What's Listening on Ports
# ==========================================
print_header "2. Port Usage Analysis"

echo "Checking DNS port 53..."
PORT_53=$(sudo lsof -i :53 2>/dev/null | grep -v COMMAND)
if [ -n "$PORT_53" ]; then
    if echo "$PORT_53" | grep -q dnsmasq; then
        print_pass "dnsmasq is listening on port 53"
    else
        print_fail "Port 53 is used by another service:"
        echo "$PORT_53"
        print_info "Fix: Stop the conflicting service or configure dnsmasq to use different port"
        ((ISSUES_FOUND++))
    fi
else
    print_fail "Nothing is listening on port 53"
    print_info "This means dnsmasq DNS is not working"
    ((ISSUES_FOUND++))
fi

echo -e "\nChecking DHCP port 67..."
PORT_67=$(sudo lsof -i :67 2>/dev/null | grep -v COMMAND)
if [ -n "$PORT_67" ]; then
    if echo "$PORT_67" | grep -q dnsmasq; then
        print_pass "dnsmasq is listening on port 67"
    else
        print_fail "Port 67 is used by another service:"
        echo "$PORT_67"
        print_info "Fix: Stop the conflicting service"
        ((ISSUES_FOUND++))
    fi
else
    print_fail "Nothing is listening on port 67 (CRITICAL)"
    print_info "This is why BOOTP requests from LPAR are failing"
    ((ISSUES_FOUND++))
fi

echo -e "\nChecking TFTP port 69..."
PORT_69=$(sudo lsof -i :69 2>/dev/null | grep -v COMMAND)
if [ -n "$PORT_69" ]; then
    if echo "$PORT_69" | grep -q dnsmasq; then
        print_pass "dnsmasq is listening on port 69"
    else
        print_fail "Port 69 is used by another service:"
        echo "$PORT_69"
        print_info "Fix: Stop the conflicting service"
        ((ISSUES_FOUND++))
    fi
else
    print_fail "Nothing is listening on port 69"
    print_info "This means TFTP boot will fail"
    ((ISSUES_FOUND++))
fi

# ==========================================
# 3. Check Interface Configuration
# ==========================================
print_header "3. Network Interface Analysis"

# Get configured interface from dnsmasq.conf
CONFIGURED_IFACE=$(grep "^interface=" /etc/dnsmasq.conf 2>/dev/null | cut -d= -f2)

if [ -n "$CONFIGURED_IFACE" ]; then
    print_info "dnsmasq configured to use interface: $CONFIGURED_IFACE"
    
    # Check if interface exists
    if ip link show "$CONFIGURED_IFACE" &>/dev/null; then
        print_pass "Interface $CONFIGURED_IFACE exists"
        
        # Check if interface is UP
        if ip link show "$CONFIGURED_IFACE" | grep -q "state UP"; then
            print_pass "Interface $CONFIGURED_IFACE is UP"
        else
            print_fail "Interface $CONFIGURED_IFACE is DOWN"
            print_info "Fix: sudo ip link set $CONFIGURED_IFACE up"
            ((ISSUES_FOUND++))
        fi
        
        # Check if interface has helper IP
        if ip addr show "$CONFIGURED_IFACE" | grep -q "$HELPER_IP"; then
            print_pass "Interface $CONFIGURED_IFACE has helper IP ($HELPER_IP)"
        else
            print_fail "Interface $CONFIGURED_IFACE does NOT have helper IP ($HELPER_IP)"
            print_info "IPs on $CONFIGURED_IFACE:"
            ip addr show "$CONFIGURED_IFACE" | grep "inet " | awk '{print "  " $2}'
            ((ISSUES_FOUND++))
        fi
    else
        print_fail "Interface $CONFIGURED_IFACE does NOT exist"
        print_info "Fix: Update dnsmasq.conf with correct interface name"
        ((ISSUES_FOUND++))
    fi
else
    print_info "No specific interface configured (listening on all interfaces)"
fi

# Find correct interface with helper IP
print_info "Finding interface with helper IP..."
CORRECT_IFACE=$(ip addr show | grep -B2 "$HELPER_IP" | head -1 | awk '{print $2}' | tr -d ':')

if [ -n "$CORRECT_IFACE" ]; then
    print_pass "Helper IP found on interface: $CORRECT_IFACE"
    
    if [ -n "$CONFIGURED_IFACE" ] && [ "$CONFIGURED_IFACE" != "$CORRECT_IFACE" ]; then
        print_fail "dnsmasq is configured for wrong interface!"
        print_info "Configured: $CONFIGURED_IFACE"
        print_info "Should be: $CORRECT_IFACE"
        print_info "Fix: Update /etc/dnsmasq.conf to use interface=$CORRECT_IFACE"
        ((ISSUES_FOUND++))
    fi
else
    print_fail "Helper IP $HELPER_IP not found on any interface!"
    print_info "Available interfaces and IPs:"
    ip addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'
    print_info "Fix: Assign $HELPER_IP to a network interface"
    ((ISSUES_FOUND++))
fi

# ==========================================
# 4. Check dnsmasq Configuration
# ==========================================
print_header "4. dnsmasq Configuration Check"

if [ -f /etc/dnsmasq.conf ]; then
    print_pass "dnsmasq.conf exists"
    
    # Check for DHCP configuration
    if grep -q "^dhcp-range=" /etc/dnsmasq.conf; then
        print_pass "DHCP range configured"
    else
        print_fail "No DHCP range configured"
        ((ISSUES_FOUND++))
    fi
    
    if grep -q "^dhcp-host=" /etc/dnsmasq.conf; then
        print_pass "DHCP host entries configured"
    else
        print_fail "No DHCP host entries configured"
        ((ISSUES_FOUND++))
    fi
    
    # Check for TFTP configuration
    if grep -q "^enable-tftp" /etc/dnsmasq.conf; then
        print_pass "TFTP is enabled"
    else
        print_fail "TFTP is NOT enabled"
        ((ISSUES_FOUND++))
    fi
    
    if grep -q "^tftp-root=" /etc/dnsmasq.conf; then
        print_pass "TFTP root configured"
    else
        print_fail "TFTP root NOT configured"
        ((ISSUES_FOUND++))
    fi
else
    print_fail "dnsmasq.conf does NOT exist"
    ((ISSUES_FOUND++))
fi

# Test configuration syntax
if dnsmasq --test &>/dev/null; then
    print_pass "dnsmasq configuration syntax is valid"
else
    print_fail "dnsmasq configuration has syntax errors"
    print_info "Run: sudo dnsmasq --test"
    ((ISSUES_FOUND++))
fi

# ==========================================
# 5. Check dnsmasq Logs
# ==========================================
print_header "5. Recent dnsmasq Logs"

print_info "Last 10 log entries:"
journalctl -u dnsmasq --since "10 minutes ago" --no-pager | tail -10 | while read line; do
    echo "  $line"
done

echo ""
print_info "Errors/Warnings in last 10 minutes:"
ERROR_COUNT=$(journalctl -u dnsmasq --since "10 minutes ago" --no-pager | grep -i -E "error|fail|warn" | wc -l)
if [ "$ERROR_COUNT" -gt 0 ]; then
    print_warn "Found $ERROR_COUNT error/warning messages:"
    journalctl -u dnsmasq --since "10 minutes ago" --no-pager | grep -i -E "error|fail|warn" | tail -5 | while read line; do
        echo "  $line"
    done
else
    print_pass "No errors or warnings in recent logs"
fi

# ==========================================
# 6. Summary and Recommendations
# ==========================================
print_header "Diagnostic Summary"

echo "Issues found: $ISSUES_FOUND"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "✓ NO ISSUES FOUND"
    echo "==========================================${NC}"
    echo ""
    echo "dnsmasq appears to be configured correctly."
    echo "If BOOTP is still failing, check:"
    echo "  1. Firewall: sudo firewall-cmd --list-all"
    echo "  2. Network connectivity between helper and LPAR"
    echo "  3. LPAR network configuration"
else
    echo -e "${RED}=========================================="
    echo "✗ $ISSUES_FOUND ISSUE(S) FOUND"
    echo "==========================================${NC}"
    echo ""
    echo "Recommended actions:"
    echo ""
    
    if [ -z "$PORT_67" ]; then
        echo "1. CRITICAL: dnsmasq not listening on DHCP port 67"
        echo "   This is why BOOTP requests are failing"
        echo ""
    fi
    
    if [ -n "$CONFIGURED_IFACE" ] && [ "$CONFIGURED_IFACE" != "$CORRECT_IFACE" ]; then
        echo "2. Fix interface configuration:"
        echo "   sudo sed -i 's/^interface=.*/interface=$CORRECT_IFACE/' /etc/dnsmasq.conf"
        echo "   sudo systemctl restart dnsmasq"
        echo ""
    fi
    
    if ! systemctl is-active --quiet dnsmasq; then
        echo "3. Start dnsmasq service:"
        echo "   sudo systemctl start dnsmasq"
        echo ""
    fi
    
    echo "To automatically fix these issues, run:"
    echo "  sudo ./fix_dnsmasq_ports.sh $VARS_FILE"
fi

exit $ISSUES_FOUND

# Made with Bob
