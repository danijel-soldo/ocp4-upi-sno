#!/bin/bash
#
# dnsmasq Port Binding Diagnostic and Fix Script
# Diagnoses why dnsmasq is not listening on required ports and attempts to fix it
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
    HELPER_IP=$(grep -A10 "^dhcp:" "$VARS_FILE" | grep "router:" | awk '{print $2}' | tr -d '"')
else
    HELPER_IP="129.40.98.129"
fi

print_header "dnsmasq Port Binding Diagnostic and Fix"
print_info "Helper IP: $HELPER_IP"

# ==========================================
# 1. Check dnsmasq Service Status
# ==========================================
print_header "1. Checking dnsmasq Service"

if systemctl is-active --quiet dnsmasq; then
    print_pass "dnsmasq service is running"
    DNSMASQ_PID=$(pgrep dnsmasq)
    print_info "dnsmasq PID: $DNSMASQ_PID"
else
    print_fail "dnsmasq service is NOT running"
    print_info "Attempting to start dnsmasq..."
    sudo systemctl start dnsmasq
    sleep 2
    if systemctl is-active --quiet dnsmasq; then
        print_pass "dnsmasq started successfully"
    else
        print_fail "Failed to start dnsmasq"
        print_info "Check logs: sudo journalctl -u dnsmasq -n 20"
        exit 1
    fi
fi

# ==========================================
# 2. Check What's Listening on Ports
# ==========================================
print_header "2. Checking Port Usage"

echo "Checking DNS port 53..."
PORT_53=$(sudo lsof -i :53 2>/dev/null | grep -v COMMAND)
if [ -n "$PORT_53" ]; then
    if echo "$PORT_53" | grep -q dnsmasq; then
        print_pass "dnsmasq is listening on port 53"
    else
        print_fail "Port 53 is used by another service:"
        echo "$PORT_53"
        print_info "Conflicting service detected"
    fi
else
    print_fail "Nothing is listening on port 53"
fi

echo -e "\nChecking DHCP port 67..."
PORT_67=$(sudo lsof -i :67 2>/dev/null | grep -v COMMAND)
if [ -n "$PORT_67" ]; then
    if echo "$PORT_67" | grep -q dnsmasq; then
        print_pass "dnsmasq is listening on port 67"
    else
        print_fail "Port 67 is used by another service:"
        echo "$PORT_67"
    fi
else
    print_fail "Nothing is listening on port 67 (CRITICAL)"
fi

echo -e "\nChecking TFTP port 69..."
PORT_69=$(sudo lsof -i :69 2>/dev/null | grep -v COMMAND)
if [ -n "$PORT_69" ]; then
    if echo "$PORT_69" | grep -q dnsmasq; then
        print_pass "dnsmasq is listening on port 69"
    else
        print_fail "Port 69 is used by another service:"
        echo "$PORT_69"
    fi
else
    print_fail "Nothing is listening on port 69"
fi

# ==========================================
# 3. Check Interface Configuration
# ==========================================
print_header "3. Checking Network Interface"

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
            INTERFACE_DOWN=true
        fi
        
        # Check if interface has helper IP
        if ip addr show "$CONFIGURED_IFACE" | grep -q "$HELPER_IP"; then
            print_pass "Interface $CONFIGURED_IFACE has helper IP ($HELPER_IP)"
        else
            print_fail "Interface $CONFIGURED_IFACE does NOT have helper IP ($HELPER_IP)"
            print_info "IPs on $CONFIGURED_IFACE:"
            ip addr show "$CONFIGURED_IFACE" | grep "inet " | awk '{print "  " $2}'
            WRONG_INTERFACE=true
        fi
    else
        print_fail "Interface $CONFIGURED_IFACE does NOT exist"
        INTERFACE_MISSING=true
    fi
else
    print_info "No specific interface configured (should listen on all)"
fi

# Find correct interface with helper IP
print_info "Finding interface with helper IP..."
CORRECT_IFACE=$(ip addr show | grep -B2 "$HELPER_IP" | head -1 | awk '{print $2}' | tr -d ':')

if [ -n "$CORRECT_IFACE" ]; then
    print_pass "Helper IP found on interface: $CORRECT_IFACE"
else
    print_fail "Helper IP $HELPER_IP not found on any interface!"
    print_info "Available interfaces:"
    ip addr show | grep "^[0-9]" | awk '{print "  " $2 " - " $0}' | grep "inet "
    exit 1
fi

# ==========================================
# 4. Check dnsmasq Logs for Errors
# ==========================================
print_header "4. Checking dnsmasq Logs"

print_info "Recent dnsmasq errors/warnings:"
sudo journalctl -u dnsmasq --since "10 minutes ago" --no-pager | grep -i -E "error|fail|warn" | tail -10

# ==========================================
# 5. Determine Fix Needed
# ==========================================
print_header "5. Determining Fix"

FIX_NEEDED=false

if [ "$INTERFACE_MISSING" = true ] || [ "$WRONG_INTERFACE" = true ]; then
    print_warn "Interface configuration needs to be fixed"
    FIX_NEEDED=true
    FIX_TYPE="interface"
elif [ "$INTERFACE_DOWN" = true ]; then
    print_warn "Interface needs to be brought UP"
    FIX_NEEDED=true
    FIX_TYPE="interface_down"
elif [ -z "$PORT_67" ]; then
    print_warn "dnsmasq not listening on ports - needs restart"
    FIX_NEEDED=true
    FIX_TYPE="restart"
fi

if [ "$FIX_NEEDED" = false ]; then
    print_pass "No fix needed - dnsmasq appears to be working"
    exit 0
fi

# ==========================================
# 6. Apply Fix
# ==========================================
print_header "6. Applying Fix"

case "$FIX_TYPE" in
    interface)
        print_info "Fixing interface configuration..."
        print_info "Changing from '$CONFIGURED_IFACE' to '$CORRECT_IFACE'"
        
        # Backup config
        sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup.$(date +%Y%m%d_%H%M%S)
        
        # Update interface
        if [ -n "$CONFIGURED_IFACE" ]; then
            sudo sed -i "s/^interface=.*/interface=$CORRECT_IFACE/" /etc/dnsmasq.conf
        else
            # Add interface line after domain line
            sudo sed -i "/^domain=/a interface=$CORRECT_IFACE" /etc/dnsmasq.conf
        fi
        
        print_pass "Updated dnsmasq.conf"
        
        # Restart dnsmasq
        print_info "Restarting dnsmasq..."
        sudo systemctl restart dnsmasq
        sleep 2
        ;;
        
    interface_down)
        print_info "Bringing interface UP..."
        sudo ip link set "$CONFIGURED_IFACE" up
        sleep 1
        
        print_info "Restarting dnsmasq..."
        sudo systemctl restart dnsmasq
        sleep 2
        ;;
        
    restart)
        print_info "Restarting dnsmasq..."
        sudo systemctl restart dnsmasq
        sleep 2
        ;;
esac

# ==========================================
# 7. Verify Fix
# ==========================================
print_header "7. Verifying Fix"

# Check if dnsmasq is running
if systemctl is-active --quiet dnsmasq; then
    print_pass "dnsmasq is running"
else
    print_fail "dnsmasq failed to start"
    print_info "Check logs: sudo journalctl -u dnsmasq -n 20"
    exit 1
fi

# Check ports again
sleep 2

echo "Checking ports after fix..."
PORTS_OK=true

if sudo lsof -i :53 2>/dev/null | grep -q dnsmasq; then
    print_pass "dnsmasq listening on port 53 (DNS)"
else
    print_fail "dnsmasq NOT listening on port 53"
    PORTS_OK=false
fi

if sudo lsof -i :67 2>/dev/null | grep -q dnsmasq; then
    print_pass "dnsmasq listening on port 67 (DHCP) ✓"
else
    print_fail "dnsmasq NOT listening on port 67"
    PORTS_OK=false
fi

if sudo lsof -i :69 2>/dev/null | grep -q dnsmasq; then
    print_pass "dnsmasq listening on port 69 (TFTP)"
else
    print_fail "dnsmasq NOT listening on port 69"
    PORTS_OK=false
fi

# ==========================================
# 8. Summary
# ==========================================
print_header "Summary"

if [ "$PORTS_OK" = true ]; then
    echo -e "${GREEN}=========================================="
    echo "✓ FIX SUCCESSFUL"
    echo "==========================================${NC}"
    echo ""
    echo "dnsmasq is now listening on all required ports."
    echo "You can proceed with LPAR netboot."
    echo ""
    echo "Verify with: sudo netstat -tulpn | grep dnsmasq"
    exit 0
else
    echo -e "${RED}=========================================="
    echo "✗ FIX FAILED"
    echo "==========================================${NC}"
    echo ""
    echo "dnsmasq is still not listening on required ports."
    echo ""
    echo "Additional troubleshooting needed:"
    echo "1. Check dnsmasq logs: sudo journalctl -u dnsmasq -n 50"
    echo "2. Test config: sudo dnsmasq --test"
    echo "3. Check for port conflicts: sudo lsof -i :67"
    echo "4. Try manual start: sudo dnsmasq --no-daemon --log-queries"
    exit 1
fi

# Made with Bob
