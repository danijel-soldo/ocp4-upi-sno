# Testing Guide for Static IP Feature

## Overview
This directory contains tests to validate the static IP feature without performing actual OpenShift installation.

## Test Files

### 1. test_static_ip.yml
Comprehensive Ansible playbook that tests all aspects of the static IP feature.

### 2. test_templates.sh (Shell Script)
Quick shell-based tests for template rendering and configuration validation.

## Running Tests

### Method 1: Shell Script (Recommended - No Dependencies)

```bash
# From project root
bash ocp4-upi-sno/tests/test_templates.sh

# Or from tests directory
cd ocp4-upi-sno/tests
./test_templates.sh
```

**What it tests:**
- ✅ Template files existence
- ✅ Validation task existence
- ✅ Configuration parameters
- ✅ Conditional DHCP logic
- ✅ GRUB IP configuration
- ✅ Netboot command variations
- ✅ Firewall port configuration
- ✅ Documentation completeness
- ✅ Backward compatibility
- ✅ IP format validation
- ✅ MAC format validation
- ✅ Static IP parameters in GRUB
- ✅ Netboot -D flag handling

**Expected Output:**
```
==========================================
Static IP Feature - Shell Tests
==========================================
...
==========================================
TEST SUMMARY
==========================================
Total Tests: 15
Passed: 15
Failed: 0
==========================================
All tests passed successfully!
```

**Advantages:**
- No dependencies required (pure bash)
- Fast execution (< 1 second)
- Works on any system with bash
- Easy to integrate into CI/CD

### Method 2: Ansible Playbook (If Ansible is Available)

**Note:** This method requires Ansible to be installed. If you don't have Ansible, use the shell script method above.

```bash
cd ocp4-upi-sno
ansible-playbook -i localhost, tests/test_static_ip.yml
```

**What it tests:**
- ✅ DHCP mode configuration (default)
- ✅ Static IP mode configuration
- ✅ GRUB configuration with DHCP
- ✅ GRUB configuration with static IP
- ✅ Firewall ports with DHCP
- ✅ Firewall ports without DHCP
- ✅ Netboot command with DHCP
- ✅ Netboot command without DHCP
- ✅ Backward compatibility
- ✅ IP address format validation
- ✅ MAC address format validation

## Test Coverage

### Template Tests
| Test | DHCP Mode | Static IP Mode |
|------|-----------|----------------|
| dnsmasq.conf rendering | ✅ | ✅ |
| DHCP section present | ✅ | ❌ |
| TFTP enabled | ✅ | ✅ |
| DNS configuration | ✅ | ✅ |

### Configuration Tests
| Test | Description |
|------|-------------|
| IP format validation | Validates IPv4 address format |
| MAC format validation | Validates MAC address format |
| Required parameters | Checks all required vars are present |
| Mode detection | Verifies correct mode is detected |

### Logic Tests
| Test | Description |
|------|-------------|
| GRUB IP parameter | Verifies correct IP config in GRUB |
| Netboot command | Validates lpar_netboot flags |
| Firewall ports | Checks correct ports are opened |
| Backward compatibility | Ensures defaults work correctly |

## Manual Testing Checklist

For thorough validation, perform these manual checks:

### Pre-Installation Tests

1. **Configuration Validation**
   ```bash
   # Test with DHCP enabled
   ansible-playbook -i inventory tasks/main.yml --check
   
   # Test with DHCP disabled
   # (Edit vars file: dhcp.enabled: false)
   ansible-playbook -i inventory tasks/main.yml --check
   ```

2. **Template Rendering**
   ```bash
   # Render dnsmasq config for DHCP mode
   ansible localhost -m template \
     -a "src=templates/dnsmasq.conf.j2 dest=/tmp/dnsmasq-dhcp.conf" \
     -e "dhcp={enabled: true, router: '192.168.1.1', netmask: '255.255.255.0'}" \
     -e "dns={clusterid: 'sno', domain: 'test.lab', forwarder1: '8.8.8.8'}" \
     -e "sno={ipaddr: '192.168.1.10', macaddr: 'fa:00:00:00:00:01', name: 'sno'}" \
     -e "helper={ipaddr: '192.168.1.2'}" \
     -e "networkifacename=eth0"
   
   # Check the output
   cat /tmp/dnsmasq-dhcp.conf
   ```

3. **Validation Task**
   ```bash
   # Run only validation
   ansible-playbook -i inventory tasks/validate_config.yaml
   ```

### Post-Configuration Tests

After running the playbook (without actual installation):

1. **Check dnsmasq Configuration**
   ```bash
   # Verify dnsmasq config
   cat /etc/dnsmasq.conf
   
   # Check for DHCP section (should exist in DHCP mode only)
   grep -A 10 "# DHCP" /etc/dnsmasq.conf
   
   # Verify TFTP is enabled
   grep "enable-tftp" /etc/dnsmasq.conf
   ```

2. **Check GRUB Configuration**
   ```bash
   # View GRUB config
   cat /var/lib/tftpboot/boot/grub2/grub.cfg
   
   # Check IP configuration parameter
   # DHCP mode should have: ip=dhcp
   # Static mode should have: ip=<ip>::<gateway>:<netmask>:...
   grep "ip=" /var/lib/tftpboot/boot/grub2/grub.cfg
   ```

3. **Check Firewall Rules**
   ```bash
   # List firewall rules
   firewall-cmd --list-all
   
   # Check if DHCP port is open (should be in DHCP mode only)
   firewall-cmd --list-ports | grep "67/udp"
   ```

4. **Verify Services**
   ```bash
   # Check dnsmasq status
   systemctl status dnsmasq
   
   # Check httpd status
   systemctl status httpd
   
   # Verify DNS resolution
   dig @localhost api.sno.test.lab
   ```

## Test Scenarios

### Scenario 1: Fresh Installation with DHCP
```yaml
dhcp:
  enabled: true  # or omit (defaults to true)
  router: "192.168.79.2"
  netmask: "255.255.255.0"
```

**Expected Results:**
- dnsmasq provides DHCP, DNS, and TFTP
- Port 67/udp is open
- GRUB uses `ip=dhcp`
- lpar_netboot includes `-D` flag

### Scenario 2: Fresh Installation with Static IP
```yaml
dhcp:
  enabled: false
  router: "192.168.79.2"
  netmask: "255.255.255.0"
```

**Expected Results:**
- dnsmasq provides only DNS and TFTP
- Port 67/udp is NOT open
- GRUB uses full static IP parameters
- lpar_netboot does NOT include `-D` flag

### Scenario 3: Migration from DHCP to Static IP
1. Run with `dhcp.enabled: true`
2. Change to `dhcp.enabled: false`
3. Re-run playbook

**Expected Results:**
- dnsmasq reconfigured to DNS-only
- DHCP port closed
- GRUB updated with static parameters
- No errors or warnings

### Scenario 4: Backward Compatibility
```yaml
dhcp:
  router: "192.168.79.2"
  netmask: "255.255.255.0"
  # enabled not specified
```

**Expected Results:**
- Defaults to DHCP mode (enabled: true)
- All DHCP features work as before
- No breaking changes

## Troubleshooting Tests

### Test 1: Validation Failures
```bash
# Test with missing required parameter
ansible-playbook -i inventory tasks/validate_config.yaml \
  -e "dhcp={enabled: false}" \
  -e "sno={name: 'sno'}"  # Missing ipaddr, macaddr, etc.
```

**Expected:** Clear error message about missing parameters

### Test 2: Invalid IP Format
```bash
# Test with invalid IP
ansible-playbook -i inventory tasks/validate_config.yaml \
  -e "sno={ipaddr: '999.999.999.999', ...}"
```

**Expected:** Error about invalid IP format

### Test 3: Invalid MAC Format
```bash
# Test with invalid MAC
ansible-playbook -i inventory tasks/validate_config.yaml \
  -e "sno={macaddr: 'invalid:mac', ...}"
```

**Expected:** Error about invalid MAC format

## Continuous Integration

For CI/CD pipelines, use this command:

```bash
#!/bin/bash
set -e

echo "Running static IP feature tests..."

# Run Ansible tests
ansible-playbook -i localhost, tests/test_static_ip.yml

# Run shell tests
cd tests && ./test_templates.sh

echo "All tests passed!"
```

## Test Results Interpretation

### Success Indicators
- ✅ All tests show "PASSED"
- ✅ No failed assertions
- ✅ Templates render correctly
- ✅ Validation catches errors appropriately

### Failure Indicators
- ❌ Any test shows "FAILED"
- ❌ Templates don't render
- ❌ Validation doesn't catch invalid input
- ❌ Configuration files have incorrect content

## Adding New Tests

To add a new test to the test suite:

1. Add a new test block in `test_static_ip.yml`:
```yaml
- name: "TEST X: Your test description"
  block:
    - name: Test step 1
      # Your test logic
    
    - name: Record test result
      set_fact:
        test_results: "{{ test_results + ['✅ TEST X PASSED: Description'] }}"
  rescue:
    - set_fact:
        test_results: "{{ test_results + ['❌ TEST X FAILED: Description'] }}"
```

2. Update this README with test description

3. Run the full test suite to verify

## Support

For test failures or questions:
1. Review test output carefully
2. Check [STATIC_IP_GUIDE.md](../STATIC_IP_GUIDE.md)
3. Verify your test environment matches requirements
4. Check Ansible version compatibility