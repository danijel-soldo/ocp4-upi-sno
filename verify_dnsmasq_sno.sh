#!/bin/bash
#
# Comprehensive dnsmasq Verification Script for SNO Static IP Installation
# This script verifies all aspects of dnsmasq configuration for Single Node OpenShift
# with static IP networking (no Day 2 workers)
#

# Don't exit on errors - we want to run all checks
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}=========================================="
    echo "$1"
    echo -e "==========================================${NC}\n"
}

print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASS++))
}

print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAIL++))
}

print_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    ((WARN++))
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

# Load configuration from vars file if provided
VARS_FILE="${1:-my-vars.yaml}"

if [ -f "$VARS_FILE" ]; then
    print_info "Loading configuration from $VARS_FILE"
    
    # Extract key values (basic YAML parsing)
    SNO_IP=$(grep -A5 "^sno:" "$VARS_FILE" | grep "ipaddr:" | awk '{print $2}' | tr -d '"')
    SNO_MAC=$(grep -A5 "^sno:" "$VARS_FILE" | grep "macaddr:" | awk '{print $2}' | tr -d '"')
    SNO_NAME=$(grep -A5 "^sno:" "$VARS_FILE" | grep "name:" | awk '{print $2}' | tr -d '"')
    HELPER_IP=$(grep -A10 "^dhcp:" "$VARS_FILE" | grep "router:" | awk '{print $2}' | tr -d '"')
    DOMAIN=$(grep -A5 "^dns:" "$VARS_FILE" | grep "domain:" | awk '{print $2}' | tr -d '"')
else
    print_warn "Vars file not found: $VARS_FILE"
    print_info "Using default values for verification"
    SNO_IP="129.40.98.130"
    SNO_MAC="fa:97:b5:dc:aa:20"
    SNO_NAME="sno"
    HELPER_IP="129.40.98.129"
    DOMAIN="cecc.ihost.com"
fi

print_info "Configuration:"
print_info "  SNO IP: $SNO_IP"
print_info "  SNO MAC: $SNO_MAC"
print_info "  SNO Name: $SNO_NAME"
print_info "  Helper IP: $HELPER_IP"
print_info "  Domain: $DOMAIN"

# ==========================================
# 1. Check dnsmasq Service Status
# ==========================================
print_header "1. dnsmasq Service Status"

if systemctl is-active --quiet dnsmasq; then
    print_pass "dnsmasq service is running"
else
    print_fail "dnsmasq service is NOT running"
    print_info "Fix: sudo systemctl start dnsmasq"
fi

if systemctl is-enabled --quiet dnsmasq; then
    print_pass "dnsmasq service is enabled"
else
    print_warn "dnsmasq service is not enabled (won't start on boot)"
    print_info "Fix: sudo systemctl enable dnsmasq"
fi

# ==========================================
# 2. Check dnsmasq Configuration File
# ==========================================
print_header "2. dnsmasq Configuration File"

if [ -f /etc/dnsmasq.conf ]; then
    print_pass "dnsmasq.conf exists"
else
    print_fail "dnsmasq.conf does NOT exist"
    exit 1
fi

# Check configuration syntax
if dnsmasq --test &>/dev/null; then
    print_pass "dnsmasq configuration syntax is valid"
else
    print_fail "dnsmasq configuration has syntax errors"
    dnsmasq --test
fi

# ==========================================
# 3. Check DHCP/BOOTP Configuration
# ==========================================
print_header "3. DHCP/BOOTP Configuration"

# Check dhcp-range
if grep -q "^dhcp-range=" /etc/dnsmasq.conf; then
    DHCP_RANGE=$(grep "^dhcp-range=" /etc/dnsmasq.conf)
    print_pass "DHCP range configured: $DHCP_RANGE"
    
    if echo "$DHCP_RANGE" | grep -q "$SNO_IP"; then
        print_pass "DHCP range includes SNO IP ($SNO_IP)"
    else
        print_fail "DHCP range does NOT include SNO IP ($SNO_IP)"
    fi
else
    print_fail "No dhcp-range configured"
fi

# Check dhcp-host for SNO
if grep -q "^dhcp-host=.*$SNO_MAC" /etc/dnsmasq.conf; then
    DHCP_HOST=$(grep "^dhcp-host=.*$SNO_MAC" /etc/dnsmasq.conf)
    print_pass "DHCP host entry for SNO MAC found: $DHCP_HOST"
    
    if echo "$DHCP_HOST" | grep -q "$SNO_IP"; then
        print_pass "DHCP host entry has correct IP ($SNO_IP)"
    else
        print_fail "DHCP host entry has wrong IP (expected $SNO_IP)"
    fi
else
    print_fail "No dhcp-host entry for SNO MAC ($SNO_MAC)"
fi

# Check dhcp-ignore (should ignore unknown MACs)
if grep -q "^dhcp-ignore=tag:!known" /etc/dnsmasq.conf; then
    print_pass "DHCP configured to ignore unknown MACs (security)"
else
    print_warn "DHCP not configured to ignore unknown MACs"
fi

# ==========================================
# 4. Check TFTP Configuration
# ==========================================
print_header "4. TFTP Configuration"

if grep -q "^enable-tftp" /etc/dnsmasq.conf; then
    print_pass "TFTP is enabled"
else
    print_fail "TFTP is NOT enabled"
fi

if grep -q "^tftp-root=" /etc/dnsmasq.conf; then
    TFTP_ROOT=$(grep "^tftp-root=" /etc/dnsmasq.conf | cut -d= -f2)
    print_pass "TFTP root configured: $TFTP_ROOT"
    
    if [ -d "$TFTP_ROOT" ]; then
        print_pass "TFTP root directory exists"
    else
        print_fail "TFTP root directory does NOT exist: $TFTP_ROOT"
    fi
else
    print_fail "No tftp-root configured"
fi

if grep -q "^dhcp-boot=" /etc/dnsmasq.conf; then
    DHCP_BOOT=$(grep "^dhcp-boot=" /etc/dnsmasq.conf | cut -d= -f2)
    print_pass "DHCP boot file configured: $DHCP_BOOT"
    
    # Check if boot file exists
    if [ -n "$TFTP_ROOT" ] && [ -f "$TFTP_ROOT/$DHCP_BOOT" ]; then
        print_pass "Boot file exists: $TFTP_ROOT/$DHCP_BOOT"
    else
        print_fail "Boot file does NOT exist: $TFTP_ROOT/$DHCP_BOOT"
    fi
else
    print_fail "No dhcp-boot configured"
fi

# ==========================================
# 5. Check TFTP Files
# ==========================================
print_header "5. TFTP Files Verification"

if [ -n "$TFTP_ROOT" ] && [ -d "$TFTP_ROOT" ]; then
    # Check for RHCOS files
    if [ -d "$TFTP_ROOT/rhcos" ]; then
        print_pass "RHCOS directory exists"
        
        if [ -f "$TFTP_ROOT/rhcos/kernel" ]; then
            KERNEL_SIZE=$(du -h "$TFTP_ROOT/rhcos/kernel" | cut -f1)
            print_pass "Kernel file exists ($KERNEL_SIZE)"
        else
            print_fail "Kernel file missing: $TFTP_ROOT/rhcos/kernel"
        fi
        
        if [ -f "$TFTP_ROOT/rhcos/initramfs.img" ]; then
            INITRAMFS_SIZE=$(du -h "$TFTP_ROOT/rhcos/initramfs.img" | cut -f1)
            print_pass "Initramfs file exists ($INITRAMFS_SIZE)"
        else
            print_fail "Initramfs file missing: $TFTP_ROOT/rhcos/initramfs.img"
        fi
    else
        print_fail "RHCOS directory missing: $TFTP_ROOT/rhcos"
    fi
    
    # Check for GRUB files
    if [ -d "$TFTP_ROOT/grub" ] || [ -d "$TFTP_ROOT/boot/grub2" ]; then
        print_pass "GRUB directory exists"
        
        # Check for grub.cfg
        if [ -f "$TFTP_ROOT/grub/grub.cfg" ]; then
            print_pass "GRUB config exists: $TFTP_ROOT/grub/grub.cfg"
        elif [ -f "$TFTP_ROOT/boot/grub2/grub.cfg" ]; then
            print_pass "GRUB config exists: $TFTP_ROOT/boot/grub2/grub.cfg"
        else
            print_fail "GRUB config missing"
        fi
    else
        print_fail "GRUB directory missing"
    fi
fi

# ==========================================
# 6. Check DNS Configuration
# ==========================================
print_header "6. DNS Configuration"

if grep -q "^domain=" /etc/dnsmasq.conf; then
    DNS_DOMAIN=$(grep "^domain=" /etc/dnsmasq.conf | cut -d= -f2)
    print_pass "DNS domain configured: $DNS_DOMAIN"
    
    if [ "$DNS_DOMAIN" = "$DOMAIN" ]; then
        print_pass "DNS domain matches expected ($DOMAIN)"
    else
        print_warn "DNS domain mismatch (expected $DOMAIN, got $DNS_DOMAIN)"
    fi
else
    print_warn "No DNS domain configured"
fi

if grep -q "^local=/" /etc/dnsmasq.conf; then
    print_pass "Local domain resolution configured"
else
    print_warn "Local domain resolution not configured"
fi

# Check for upstream DNS servers
UPSTREAM_COUNT=$(grep -c "^server=" /etc/dnsmasq.conf || true)
if [ "$UPSTREAM_COUNT" -gt 0 ]; then
    print_pass "Upstream DNS servers configured ($UPSTREAM_COUNT servers)"
    grep "^server=" /etc/dnsmasq.conf | while read line; do
        print_info "  $line"
    done
else
    print_warn "No upstream DNS servers configured"
fi

# ==========================================
# 7. Check Network Interface
# ==========================================
print_header "7. Network Interface Configuration"

if grep -q "^interface=" /etc/dnsmasq.conf; then
    INTERFACE=$(grep "^interface=" /etc/dnsmasq.conf | cut -d= -f2)
    print_pass "dnsmasq bound to interface: $INTERFACE"
    
    # Check if interface exists
    if ip link show "$INTERFACE" &>/dev/null; then
        print_pass "Interface $INTERFACE exists"
        
        # Check if interface is UP
        if ip link show "$INTERFACE" | grep -q "state UP"; then
            print_pass "Interface $INTERFACE is UP"
        else
            print_fail "Interface $INTERFACE is DOWN"
            print_info "Fix: sudo ip link set $INTERFACE up"
        fi
        
        # Check if interface has helper IP
        if ip addr show "$INTERFACE" | grep -q "$HELPER_IP"; then
            print_pass "Interface $INTERFACE has helper IP ($HELPER_IP)"
        else
            print_fail "Interface $INTERFACE does NOT have helper IP ($HELPER_IP)"
            print_info "Current IPs on $INTERFACE:"
            ip addr show "$INTERFACE" | grep "inet " | awk '{print "  " $2}'
        fi
    else
        print_fail "Interface $INTERFACE does NOT exist"
        print_info "Available interfaces:"
        ip link show | grep "^[0-9]" | awk '{print "  " $2}' | tr -d ':'
    fi
else
    print_warn "No specific interface configured (listening on all)"
    
    # Check if helper IP is on any interface
    if ip addr show | grep -q "$HELPER_IP"; then
        HELPER_IFACE=$(ip addr show | grep -B2 "$HELPER_IP" | head -1 | awk '{print $2}' | tr -d ':')
        print_pass "Helper IP ($HELPER_IP) found on interface: $HELPER_IFACE"
    else
        print_fail "Helper IP ($HELPER_IP) not found on any interface"
    fi
fi

# ==========================================
# 8. Check Listening Ports
# ==========================================
print_header "8. Network Ports"

# Check DNS port (53)
if netstat -tulpn 2>/dev/null | grep -q ":53.*dnsmasq"; then
    print_pass "dnsmasq listening on DNS port 53"
else
    print_fail "dnsmasq NOT listening on DNS port 53"
fi

# Check DHCP port (67)
if netstat -tulpn 2>/dev/null | grep -q ":67.*dnsmasq"; then
    print_pass "dnsmasq listening on DHCP port 67"
else
    print_fail "dnsmasq NOT listening on DHCP port 67"
fi

# Check TFTP port (69)
if netstat -tulpn 2>/dev/null | grep -q ":69.*dnsmasq"; then
    print_pass "dnsmasq listening on TFTP port 69"
else
    print_fail "dnsmasq NOT listening on TFTP port 69"
fi

# ==========================================
# 9. Check Firewall
# ==========================================
print_header "9. Firewall Configuration"

if systemctl is-active --quiet firewalld; then
    print_info "Firewalld is active"
    
    # Check DNS port
    if firewall-cmd --list-all 2>/dev/null | grep -q "53/"; then
        print_pass "Firewall allows DNS (port 53)"
    else
        print_warn "Firewall may not allow DNS (port 53)"
    fi
    
    # Check DHCP port
    if firewall-cmd --list-all 2>/dev/null | grep -q "67/"; then
        print_pass "Firewall allows DHCP (port 67)"
    else
        print_fail "Firewall does NOT allow DHCP (port 67)"
        print_info "Fix: sudo firewall-cmd --permanent --add-port=67/udp && sudo firewall-cmd --reload"
    fi
    
    # Check TFTP port
    if firewall-cmd --list-all 2>/dev/null | grep -q "69/"; then
        print_pass "Firewall allows TFTP (port 69)"
    else
        print_fail "Firewall does NOT allow TFTP (port 69)"
        print_info "Fix: sudo firewall-cmd --permanent --add-port=69/udp && sudo firewall-cmd --reload"
    fi
else
    print_warn "Firewalld is not active (firewall disabled)"
fi

# ==========================================
# 10. Check HTTP Server for Ignition
# ==========================================
print_header "10. HTTP Server (for ignition files)"

if systemctl is-active --quiet httpd; then
    print_pass "HTTP server (httpd) is running"
    
    # Check ignition directory
    if [ -d /var/www/html/ignition ]; then
        print_pass "Ignition directory exists"
        
        IGN_COUNT=$(ls -1 /var/www/html/ignition/*.ign 2>/dev/null | wc -l)
        if [ "$IGN_COUNT" -gt 0 ]; then
            print_pass "Ignition files found ($IGN_COUNT files)"
        else
            print_warn "No ignition files found in /var/www/html/ignition"
        fi
    else
        print_warn "Ignition directory missing: /var/www/html/ignition"
    fi
    
    # Check rootfs
    if [ -f /var/www/html/install/rootfs.img ]; then
        ROOTFS_SIZE=$(du -h /var/www/html/install/rootfs.img | cut -f1)
        print_pass "Rootfs image exists ($ROOTFS_SIZE)"
    else
        print_fail "Rootfs image missing: /var/www/html/install/rootfs.img"
    fi
else
    print_fail "HTTP server (httpd) is NOT running"
    print_info "Fix: sudo systemctl start httpd"
fi

# ==========================================
# 11. Check dnsmasq Logs
# ==========================================
print_header "11. Recent dnsmasq Logs"

print_info "Last 10 dnsmasq log entries:"
journalctl -u dnsmasq --since "10 minutes ago" --no-pager | tail -10 | while read line; do
    echo "  $line"
done

# Check for DHCP messages in logs
if journalctl -u dnsmasq --since "10 minutes ago" | grep -q "DHCP"; then
    print_pass "DHCP activity detected in logs"
else
    print_warn "No DHCP activity in recent logs"
fi

# ==========================================
# 12. Static IP Mode Verification
# ==========================================
print_header "12. Static IP Mode Configuration"

# Check GRUB config for static IP parameters
if [ -f "$TFTP_ROOT/grub/grub.cfg" ]; then
    GRUB_CFG="$TFTP_ROOT/grub/grub.cfg"
elif [ -f "$TFTP_ROOT/boot/grub2/grub.cfg" ]; then
    GRUB_CFG="$TFTP_ROOT/boot/grub2/grub.cfg"
else
    GRUB_CFG=""
fi

if [ -n "$GRUB_CFG" ]; then
    if grep -q "ip=$SNO_IP" "$GRUB_CFG"; then
        print_pass "GRUB config has static IP kernel parameter"
    else
        print_fail "GRUB config missing static IP kernel parameter"
    fi
    
    if grep -q "nameserver=" "$GRUB_CFG"; then
        print_pass "GRUB config has nameserver kernel parameter"
    else
        print_warn "GRUB config missing nameserver kernel parameter"
    fi
fi

# ==========================================
# Summary
# ==========================================
print_header "Verification Summary"

TOTAL=$((PASS + FAIL + WARN))
echo -e "${GREEN}Passed:${NC}  $PASS"
echo -e "${RED}Failed:${NC}  $FAIL"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "Total:   $TOTAL"

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "✓ ALL CRITICAL CHECKS PASSED"
    echo "==========================================${NC}"
    echo ""
    echo "dnsmasq is properly configured for SNO static IP installation."
    echo "You can proceed with LPAR netboot."
    exit 0
else
    echo -e "${RED}=========================================="
    echo "✗ CONFIGURATION ISSUES FOUND"
    echo "==========================================${NC}"
    echo ""
    echo "Please fix the failed checks above before proceeding."
    echo "Review the suggested fixes and re-run this script."
    exit 1
fi

# Made with Bob
