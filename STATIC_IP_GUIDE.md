# Static IP Installation Guide

## Quick Start

To install OpenShift SNO without DHCP, simply set `dhcp.enabled: false` in your variables file.

## Minimal Configuration Example

```yaml
---
helper:
  name: "helper"
  ipaddr: "192.168.79.2"

dns:
  domain: "cloud.lab"
  clusterid: "sno"
  forwarder1: "9.9.9.9"

dhcp:
  router: "192.168.79.2"
  netmask: "255.255.255.0"
  enabled: false  # <-- Set to false for static IP mode

sno:
  name: sno
  macaddr: "fa:4e:86:23:37:20"
  ipaddr: "192.168.79.10"
  disk: "/dev/sda"
  pvmcec: Server-9080-HEX-SN785EDA8
  pvmlpar: cp4d-3-worker-1

pvm_hmc: hmc_user@hmc.host.ip
```

## What Changes in Static IP Mode?

### Services
| Service | DHCP Mode | Static IP Mode |
|---------|-----------|----------------|
| DNS | ✅ Enabled | ✅ Enabled |
| DHCP | ✅ Enabled | ❌ Disabled |
| HTTP | ✅ Enabled | ✅ Enabled |
| TFTP | ✅ Enabled | ✅ Enabled |

### Network Configuration
| Aspect | DHCP Mode | Static IP Mode |
|--------|-----------|----------------|
| IP Assignment | Via DHCP | Via kernel parameters |
| Boot Command | `lpar_netboot -i -D -f ...` | `lpar_netboot -i -f ...` |
| Firewall Port 67/udp | Open | Closed |
| Network Config | DHCP lease | Static in GRUB |

### GRUB Boot Parameters

**DHCP Mode:**
```
linux "/rhcos/kernel" ip=dhcp rd.neednet=1 ...
```

**Static IP Mode:**
```
linux "/rhcos/kernel" ip=192.168.79.10::192.168.79.2:255.255.255.0:sno.sno.cloud.lab:env32:none nameserver=192.168.79.2 rd.neednet=1 ...
```

## Validation

The automation includes built-in validation that checks:
- ✅ Required parameters are defined
- ✅ IP addresses are in valid format
- ✅ MAC addresses are in valid format
- ✅ Configuration is consistent with selected mode

Run the playbook and validation will occur automatically before any changes are made.

## Troubleshooting

### Problem: "DHCP services will be DISABLED" warning
**Solution:** This is expected in static IP mode. Verify your configuration is correct and proceed.

### Problem: Node cannot get IP address
**Solution:** In static IP mode, the IP is configured via kernel parameters, not DHCP. Check:
1. GRUB configuration has correct IP parameters
2. Network interface name is correct
3. Gateway is reachable

### Problem: DNS resolution fails
**Solution:** 
1. Verify bastion IP is correct in configuration
2. Check dnsmasq is running: `systemctl status dnsmasq`
3. Test DNS: `dig @<bastion_ip> api.sno.cloud.lab`

### Problem: PXE boot fails
**Solution:**
1. Verify TFTP is enabled in dnsmasq
2. Check GRUB files exist: `ls /var/lib/tftpboot/boot/grub2/`
3. Review GRUB config: `cat /var/lib/tftpboot/boot/grub2/grub.cfg`

## Migration from DHCP to Static IP

If you have an existing DHCP-based installation and want to switch to static IP:

1. Update your variables file:
   ```yaml
   dhcp:
     enabled: false
   ```

2. Re-run the playbook:
   ```bash
   ansible-playbook -i inventory tasks/main.yml
   ```

3. The automation will:
   - Reconfigure dnsmasq (DNS-only mode)
   - Update GRUB with static IP parameters
   - Close DHCP firewall port
   - Update netboot commands

## Advantages of Static IP Mode

✅ **Compliance**: Works in environments where DHCP is prohibited  
✅ **Predictability**: No DHCP lease expiration issues  
✅ **Simplicity**: Fewer services to manage  
✅ **Security**: Reduced attack surface (no DHCP service)  
✅ **Troubleshooting**: Network config is explicit in boot parameters  

## When to Use Each Mode

### Use DHCP Mode When:
- DHCP is available and permitted
- You want traditional PXE boot experience
- You have multiple nodes to provision
- Dynamic IP assignment is preferred

### Use Static IP Mode When:
- DHCP servers are not permitted
- You need predictable, fixed IP addresses
- Security policies prohibit DHCP
- You want explicit network configuration
- Compliance requires static IP assignment

## Additional Resources

- See [README.md](README.md) for complete installation instructions
- Review [example-vars.yaml](example-vars.yaml) for all configuration options
- Check [tasks/validate_config.yaml](tasks/validate_config.yaml) for validation logic

## Support

For issues or questions:
1. Check validation output for configuration errors
2. Review dnsmasq logs: `journalctl -u dnsmasq -f`
3. Check GRUB configuration: `/var/lib/tftpboot/boot/grub2/grub.cfg`
4. Verify network connectivity from bastion to SNO node