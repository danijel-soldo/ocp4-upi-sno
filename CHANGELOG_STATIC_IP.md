# Changelog: Static IP Support

## Overview
Added support for installing OpenShift SNO without DHCP services, using only static IP configuration.

## Version
- **Feature**: Static IP Installation Mode
- **Date**: 2026-02-18
- **Compatibility**: Backward compatible - DHCP mode remains default

## Files Modified

### 1. example-vars.yaml
**Changes:**
- Added `dhcp.enabled` parameter (default: `true`)
- When set to `false`, disables DHCP services

**Example:**
```yaml
dhcp:
  router: "192.168.79.2"
  netmask: "255.255.255.0"
  enabled: false  # New parameter
```

### 2. templates/dnsmasq.conf.j2
**Changes:**
- Made DHCP and PXE sections conditional based on `dhcp.enabled`
- When DHCP disabled: only DNS and TFTP services are configured
- Removed DHCP-specific configuration when in static IP mode

**Key Logic:**
```jinja2
{% if dhcp.enabled | default(true) %}
  # DHCP and PXE configuration
{% else %}
  # TFTP only (without DHCP)
{% endif %}
```

### 3. tasks/generate_grub.yaml
**Changes:**
- Added dynamic IP configuration fact setting
- DHCP mode: uses `ip=dhcp`
- Static IP mode: uses full static IP kernel parameters
- Format: `ip=<ip>::<gateway>:<netmask>:<hostname>:<interface>:none nameserver=<dns>`

**Example Static IP Parameter:**
```
ip=192.168.79.10::192.168.79.2:255.255.255.0:sno.sno.cloud.lab:env32:none nameserver=192.168.79.2
```

### 4. tasks/netboot.yaml
**Changes:**
- Split netboot tasks into DHCP and static IP variants
- DHCP mode: uses `lpar_netboot -i -D -f ...` (with `-D` flag)
- Static IP mode: uses `lpar_netboot -i -f ...` (without `-D` flag)
- Applied to both SNO and day2 worker nodes

### 5. tasks/set_facts.yaml
**Changes:**
- Conditional firewall port configuration
- DHCP mode: includes port 67/udp
- Static IP mode: excludes port 67/udp
- All other ports remain the same

### 6. tasks/main.yml
**Changes:**
- Added validation task as first step
- Validates configuration before making any changes

## Files Created

### 1. tasks/validate_config.yaml (NEW)
**Purpose:** Comprehensive configuration validation

**Validates:**
- DHCP mode configuration
- Static IP mode requirements
- IP address formats
- MAC address formats
- Day2 worker configuration
- DNS parameters
- SNO node parameters
- HMC connection settings

**Features:**
- Clear error messages
- Success confirmations
- Mode-specific warnings
- Configuration summary

### 2. STATIC_IP_GUIDE.md (NEW)
**Purpose:** Quick reference guide for static IP installation

**Contents:**
- Quick start example
- Service comparison table
- Network configuration differences
- GRUB parameter examples
- Troubleshooting guide
- Migration instructions
- Use case recommendations

### 3. README.md (UPDATED)
**Changes:**
- Added "Installation Modes" section
- Documented DHCP vs Static IP differences
- Added "Static IP Configuration" section with:
  - Overview
  - Configuration examples
  - How it works
  - Network requirements
  - Troubleshooting
  - Advantages and limitations

## Technical Details

### Static IP Kernel Parameters
The static IP configuration is passed to the kernel during boot using this format:
```
ip=<client-ip>::<gateway>:<netmask>:<hostname>:<interface>:none nameserver=<dns-server>
```

### Network Boot Command Changes
**DHCP Mode:**
```bash
lpar_netboot -i -D -f -t ent -m <mac> -s auto -d auto -S <server> -C <client> -G <gateway> -K <netmask> ...
```

**Static IP Mode:**
```bash
lpar_netboot -i -f -t ent -m <mac> -s auto -d auto -S <server> -C <client> -G <gateway> -K <netmask> ...
```
Note: The `-D` flag (DHCP request) is removed in static IP mode.

### Service Configuration

| Service | DHCP Mode | Static IP Mode |
|---------|-----------|----------------|
| dnsmasq (DNS) | ✅ | ✅ |
| dnsmasq (DHCP) | ✅ | ❌ |
| dnsmasq (TFTP) | ✅ | ✅ |
| httpd | ✅ | ✅ |
| nfs-server | ✅ | ✅ |

### Firewall Ports

| Port | Service | DHCP Mode | Static IP Mode |
|------|---------|-----------|----------------|
| 67/udp | DHCP | ✅ | ❌ |
| 53/tcp,udp | DNS | ✅ | ✅ |
| 69/udp | TFTP | ✅ | ✅ |
| 80/tcp | HTTP | ✅ | ✅ |
| 443/tcp | HTTPS | ✅ | ✅ |
| 6443/tcp,udp | Kubernetes API | ✅ | ✅ |
| 22623/tcp,udp | Machine Config | ✅ | ✅ |
| Others | NFS, etc. | ✅ | ✅ |

## Backward Compatibility

✅ **Fully backward compatible**
- Default behavior unchanged (DHCP enabled)
- Existing configurations work without modification
- `dhcp.enabled` defaults to `true` if not specified
- All existing playbooks continue to work

## Testing Recommendations

### Test Scenarios
1. **DHCP Mode (Default)**
   - Verify DHCP services start correctly
   - Confirm PXE boot with DHCP works
   - Check port 67/udp is open

2. **Static IP Mode**
   - Verify DHCP services are disabled
   - Confirm static IP parameters in GRUB
   - Check port 67/udp is closed
   - Verify network connectivity with static IP

3. **Validation**
   - Test with missing required parameters
   - Test with invalid IP formats
   - Test with invalid MAC formats
   - Verify validation messages are clear

4. **Day2 Worker**
   - Test static IP mode with day2 worker
   - Verify both nodes get correct configuration

## Migration Path

### From DHCP to Static IP
1. Update your configuration file (e.g., `my-vars.yaml`): set `dhcp.enabled: false`
2. Re-run playbook: `ansible-playbook tasks/main.yml -e @my-vars.yaml`
3. Verify dnsmasq configuration: `cat /etc/dnsmasq.conf`
4. Test PXE boot

### From Static IP to DHCP
1. Update your configuration file (e.g., `my-vars.yaml`): set `dhcp.enabled: true`
2. Re-run playbook: `ansible-playbook tasks/main.yml -e @my-vars.yaml`
3. Verify DHCP services start: `systemctl status dnsmasq`
4. Test PXE boot

## Known Limitations

1. **Network Interface Name**: Must be known or auto-detected correctly
2. **Manual IP Management**: IPs must be managed manually in static mode
3. **No DHCP Fallback**: Once disabled, DHCP is completely unavailable
4. **Configuration Changes**: Require regenerating boot files

## Future Enhancements

Potential improvements for future versions:
- [ ] Support for multiple network interfaces
- [ ] IPv6 static configuration
- [ ] VLAN tagging support
- [ ] Bond/team interface configuration
- [ ] Automated IP conflict detection
- [ ] Integration with IPAM systems

## Support

For issues or questions:
1. Review validation output
2. Check [STATIC_IP_GUIDE.md](STATIC_IP_GUIDE.md)
3. Consult [README.md](README.md) Static IP section
4. Examine dnsmasq logs: `journalctl -u dnsmasq`
5. Verify GRUB configuration: `/var/lib/tftpboot/boot/grub2/grub.cfg`

## Contributors

- Feature implementation: IBM Bob
- Documentation: IBM Bob
- Testing: Pending user validation