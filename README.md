# Installing single node OpenShift to PowerVM

For current OpenShift release, the `openshift-install` supports to create the special ignition file for SNO installation. This method can be used for any platform.

## 📖 Quick Start

**[[View Interactive Installation Guide](https://danijel-soldo.github.io/ocp4-upi-sno/quick-start.html)]** - Open this HTML file in your browser for a comprehensive visual guide with diagrams and examples.

```bash
# Open the guide in your default browser
open docs/installation-guide.html  # macOS
xdg-open docs/installation-guide.html  # Linux
start docs/installation-guide.html  # Windows
```

## 🔧 Configuring OpenShift Version

Before running the installation, you must configure the OpenShift version in your `my-vars.yaml` file. The automation will download and install the specified version.

### Version Configuration Fields

Edit these fields in your `my-vars.yaml` (based on `example-vars.yaml`):

```yaml
# For OpenShift 4.13 (stable):
rhcos_rhcos_base: "4.13"
rhcos_rhcos_tag: "latest"
ocp_client_tag: "latest-4.13"

# For OpenShift 4.14 (stable):
rhcos_rhcos_base: "4.14"
rhcos_rhcos_tag: "latest"
ocp_client_tag: "latest-4.14"

# For OpenShift 4.15 (stable):
rhcos_rhcos_base: "4.15"
rhcos_rhcos_tag: "latest"
ocp_client_tag: "latest-4.15"

# For specific version (e.g., 4.13.10):
rhcos_rhcos_base: "4.13"
rhcos_rhcos_tag: "4.13.10"
ocp_client_tag: "4.13.10"
```

### Version Selection Guidelines

- **Use "latest"** for the most recent patch version (recommended for production)
- **Specify exact version** (e.g., "4.13.10") for reproducible installations
- **Keep versions aligned:** `rhcos_rhcos_base` and `ocp_client_tag` must match the same major.minor version
- **Check availability:** Visit [OpenShift Mirror](https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp/) to see available versions

### Complete URL Configuration

The automation automatically constructs download URLs from these settings:

```yaml
# RHCOS Downloads
rhcos_arch: "ppc64le"
rhcos_base_url: "https://mirror.openshift.com/pub/openshift-v4/{{ rhcos_arch }}/dependencies/rhcos"
rhcos_rhcos_base: "4.13"  # OpenShift major.minor version
rhcos_rhcos_tag: "latest"  # Use "latest" or specific version

# OCP Client/Installer Downloads
ocp_client_arch: "ppc64le"
ocp_base_url: "https://mirror.openshift.com/pub/openshift-v4/{{ ocp_client_arch }}/clients"
ocp_client_base: "ocp"  # Use "ocp" for stable, "ocp-dev-preview" for nightly
ocp_client_tag: "latest-4.13"  # Must match rhcos_rhcos_base version
```

**Important:** Do not modify the URL template lines (those with `{{ }}`). Only change the version-specific fields (`rhcos_rhcos_base`, `rhcos_rhcos_tag`, `ocp_client_tag`).

## 🔄 Cleanup and Reinstall

If an installation fails or you need to start over, use the provided cleanup script:

### Automated Cleanup Script

```bash
# Basic cleanup (keeps downloaded files for faster reinstall)
./cleanup_and_reinstall.sh

# Force re-download of all files
./cleanup_and_reinstall.sh --force-download

# Use custom vars file
./cleanup_and_reinstall.sh --vars-file my-custom-vars.yaml
```

**What the script does:**
1. Stops any running `openshift-install` processes
2. Cleans up the work directory (`~/ocp4-sno` by default)
3. Powers off the SNO LPAR via HMC
4. Optionally removes cached downloads to force fresh download
5. Waits for LPAR to fully power off

**After cleanup, update your configuration and reinstall:**
```bash
# Edit configuration if needed
vi my-vars.yaml

# Run installation
ansible-playbook tasks/main.yml -e @my-vars.yaml
```

### Manual Cleanup Steps

If you prefer manual cleanup or the script doesn't work:

```bash
# 1. Stop openshift-install processes
pkill -9 openshift-install

# 2. Clean work directory
rm -rf ~/ocp4-sno

# 3. Power off SNO LPAR (replace with your values)
ssh hmc_user@hmc_host "chsysstate -r lpar -m YOUR_CEC -o shutdown --immed -n YOUR_LPAR"

# 4. Optional: Force re-download
sudo rm -rf /usr/local/src/rhcos-*
sudo rm -rf /usr/local/src/openshift-*

# 5. Wait 30 seconds
sleep 30

# 6. Reinstall
ansible-playbook tasks/main.yml -e @my-vars.yaml
```

### Common Reasons for Reinstall

- **Version mismatch**: RHCOS and OpenShift versions don't match
- **Wrong disk specified**: Installation disk doesn't exist on LPAR
- **Network issues**: LPAR can't reach helper node
- **Corrupted ignition**: Ignition file has errors
- **Testing different configurations**: Trying DHCP vs static IP modes

## Requirements for installing OpenShift on a single node

To do the SNO installation, we need two VMs, one works as bastion and another one as OCP node, the minimum hardware requirements as show as below:

| VM   | vCPU  |  Memory  | Storage |
| :----|-----:|--------:|-------:|
| Bastion | 2   |  8GB    |  50 GB  |
| SNO     | 8   |  16GB   | 120GB   |

The `bastion` is used to setup required services and require to be able to run as root. The SNO node need to have the static IP assigned with internet access.

## Installation Modes

This automation supports two installation modes:

### 1. DHCP Mode (Default)
The bastion provides DHCP services along with DNS, HTTP, and TFTP. This is the traditional PXE boot approach.

### 2. Static IP Mode (No DHCP)
For environments where DHCP servers are not permitted, the automation can be configured to use only static IP addresses. In this mode:
- The bastion provides only DNS, HTTP, and TFTP services
- DHCP is completely disabled
- Network configuration is passed via kernel parameters during boot
- The `lpar_netboot` command uses static IP parameters

To enable static IP mode, set `dhcp.enabled: false` in your configuration file (e.g., `my-vars.yaml` based on `example-vars.yaml`).

## Bastion setup
The bastion's `SELINUX` has to be set to `permissive` mode, otherwise ansible playbook will fail, to do it open file `/etc/selinux/config` and set `SELINUX=permissive`.

We will use PXE for SNO installation, that requires the following services to be configured and run:
- DNS -- to define `api`, `api-int` and `*.apps`
- DHCP -- (optional, only in DHCP mode) to enable PXE and assign IP to SNO node
- HTTP -- to provide ignition and RHCOS rootfs image
- TFTP -- to enable PXE

we will install `dnsmasq` to support DNS, DHCP and PXE, `httpd` for HTTP.

Here are some values used in sample configurations:
- 9.47.87.82 -- SNO node's IP
- 9.47.87.83 -- Bastion's IP
- 9.47.95.254 -- Network route or gateway
- ocp.io  -- SNO's domain name
- sno -- SNO's cluster_id


### dnsmasq setup

Here is a sample configuration file for `/etc/dnsmasq.conf`:
```
#################################
# DNS
##################################
#domain-needed
# don't send bogus requests out on the internets
bogus-priv
# enable IPv6 Route Advertisements
enable-ra
bind-dynamic
no-hosts
#  have your simple hosts expanded to domain
expand-hosts


interface=env32
# set your domain for expand-hosts
domain=sno.ocp.io
local=/sno.ocp.io/
address=/apps.sno.ocp.io/9.47.87.82
server=9.9.9.9

addn-hosts=/etc/dnsmasq.d/addnhosts


##################################
# DHCP
##################################
dhcp-ignore=tag:!known
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

dhcp-range=9.47.87.82,static

dhcp-option=option:router,9.47.95.254
dhcp-option=option:netmask,255.255.240.0
dhcp-option=option:dns-server,9.47.87.83

dhcp-host=fa:b0:45:27:43:20,sno-82,9.47.87.82,infinite


###############################
# PXE
###############################
enable-tftp
tftp-root=/var/lib/tftpboot
dhcp-boot=boot/grub2/powerpc-ieee1275/core.elf
```
and `/etc/dnsmasq.d/addnhosts` file:
```
9.47.87.82 sno-82 api api-int
```

### PXE setup
To enable PXE for PowerVM, we need to install `grub2` with:
```shell
grub2-mknetdir --net-directory=/var/lib/tftpboot
```

Here is the sample `/var/lib/tftpboot/boot/grub2/grub.cfg`:
```shell
default=0
fallback=1
timeout=1

if [ ${net_default_mac} == fa:b0:45:27:43:20 ]; then
default=0
fallback=1
timeout=1
menuentry "CoreOS (BIOS)" {
   echo "Loading kernel"
   linux "/rhcos/kernel" ip=dhcp rd.neednet=1 ignition.platform.id=metal ignition.firstboot coreos.live.rootfs_url=http://9.47.87.83:8000/install/rootfs.img ignition.config.url=http://9.47.87.83:8000/ignition/sno.ign

   echo "Loading initrd"
   initrd  "/rhcos/initramfs.img"
}
fi
```

Download RHCOS image files from [here](https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/4.12/latest/) for PXE:
```shell
export RHCOS_URL=https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/4.12/latest/
cd /var/lib/tftpboot/rhcos
wget ${RHCOS_URL}/rhcos-live-kernel-ppc64le -o kernel
wget ${RHCOS_URL}/rhcos-live-initramfs.ppc64le.img -o initramfs.img
cd /var//var/www/html/install/
wget ${RHCOS_URL}/rhcos-live-rootfs.ppc64le.img -o rootfs.img
```

### Create the ignition file
To create the ignition file for SNO, we need to create the `install-config.yaml` file, first we need to create the work directory to hold the file:
```shell
mkdir -p ~/sno-work
cd ~/sno-work
```
Using following sample file to create the required `install-config.yaml`:
```yaml
apiVersion: v1
baseDomain: <domain>
compute:
- name: worker
  replicas: 0 
controlPlane:
  name: master
  replicas: 1 
metadata:
  name: <cluster_id>
networking: 
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 9.47.80.0/20 
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
bootstrapInPlace:
  installationDisk: <device> 
pullSecret: '<pull_secret>' 
sshKey: |
  <ssh_key> 
```
Note: 
- `<domain>`: Set the domain for your cluster, like `ocp.io`.
- `<cluster_id>`: Set the cluster_id for your cluster, like `sno`.
- `<ssh_key>`: Add the public SSH key from the administration host so that you can log in to the cluster after installation. 
- `<pull_secret>`: Copy the pull secret from the Red Hat OpenShift Cluster Manager and add the contents to this configuration setting.
- `<device>`: Provide the device name where the RHCOS will be installed, like `/dev/sda` or `/dev/disk/by-id/scsi-36005076d0281005ef000000000026803`.

Download the `openshift-install`:
```shell
wget wget https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp/4.12.0/openshift-install-linux-4.12.0.tar.gz
tar xzvf openshift-install-linux-4.12.0.tar.gz
```
Create the ignition file and copy it to http directory:
```shell
./openshift-install --dir=~/sno-work create create single-node-ignition-config
cp ~/sno-work/single-node-ignition-config.ign /var/www/html/ignition/sno.ign
restorecon -vR /var/www/html || true
```

Now `bastion` has all required files and configurations to install SNO.

## SNO installation
There two steps for SNO installation, first the SNO LPAR need to boot up with PXE, then monitor the installation progress.

### Network boot
To boot powerVM with netboot, there are two ways to do it: using SMS interactively to select bootp or using `lpar_netboot`  command on HMC. Reference to HMC doc for how to using SMS.

Here is the `lpar_netboot` command:
```shell
lpar_netboot -i -D -f -t ent -m <sno_mac> -s auto -d auto -S <server_ip> -C <sno_ip> -G <gateway> <lpar_name> default_profile <cec_name>
```
Note:
- <sno_mac>: MAC address of SNO
- <sno_ip>:  IP address of SNO
- <server_ip>: IP address of bastion (PXE server)
- <gateway>: Network's gateway IP
- <lpar_name>: SNO lpar name in HMC
- <cec_name>: System name where the sno_lpar resident at

### Monitoring the progress
After the SNO lpar boot up with PXE, we can use `openshift-install` to monitor the progress of installation.

```shell
# first need to wait for bootstrap complete
./openshift-install wait-for bootstrap-complete
# after it return successfully, using following cmd to wait for completed
./openshift-install wait-for install-complete
```
Also we can use `oc` to check installation status:
```shell
export KUBECONFIG=~/sno-work/auth/kubeconfig
# check SNO node status
oc get nodes
# check installation status
oc get clusterversion
# check cluster operators
oc get co
# check pod status
oc get pod -A
```

## Static IP Configuration

### Overview
When DHCP is not available or not permitted in your environment, you can configure the automation to use static IP addresses only. This mode disables DHCP services on the bastion while maintaining DNS, HTTP, and TFTP functionality.

### Configuration

To enable static IP mode, create your configuration file from the template and modify it:

```bash
cp example-vars.yaml my-vars.yaml
# Edit my-vars.yaml and set dhcp.enabled: false
```

Add the following to your configuration file (`my-vars.yaml`):

```yaml
dhcp:
  router: "192.168.79.2"
  netmask: "255.255.255.0"
  enabled: false  # Set to false to disable DHCP
```

### How It Works

#### 1. DNS-Only Mode
When `dhcp.enabled: false` in your configuration file, the dnsmasq configuration (`templates/dnsmasq.conf.j2`):
- Provides DNS services for cluster resolution
- Enables TFTP for PXE boot
- **Does NOT** provide DHCP services
- **Does NOT** open DHCP port (67/udp) in firewall

#### 2. Static IP Kernel Parameters
The GRUB configuration (`tasks/generate_grub.yaml`) passes static network configuration via kernel parameters:
```
ip=<ipaddr>::<gateway>:<netmask>:<hostname>:<interface>:none nameserver=<dns_server>
```

For example:
```
ip=192.168.79.10::192.168.79.2:255.255.255.0:sno.sno.cloud.lab:env32:none nameserver=192.168.79.2
```

#### 3. Network Boot with Static IP
The `lpar_netboot` command is modified to remove the `-D` flag (DHCP request) when static IP mode is enabled:
- **DHCP mode**: `lpar_netboot -i -D -f -t ent ...`
- **Static IP mode**: `lpar_netboot -i -f -t ent ...`

### Example Configuration

Complete example for static IP installation:

```yaml
---
helper:
  name: "helper"
  ipaddr: "192.168.79.2"
  networkifacename: "env32"

dns:
  domain: "cloud.lab"
  clusterid: "sno"
  forwarder1: "9.9.9.9"
  forwarder2: "8.8.4.4"

dhcp:
  router: "192.168.79.2"
  netmask: "255.255.255.0"
  enabled: false  # Disable DHCP for static IP mode

sno:
  name: sno
  macaddr: "fa:4e:86:23:37:20"
  ipaddr: "192.168.79.10"
  disk: "/dev/sda"
  pvmcec: Server-9080-HEX-SN785EDA8
  pvmlpar: cp4d-3-worker-1

pvm_hmc: hmc_user@hmc.host.ip

# ... rest of configuration
```

### Network Requirements for Static IP Mode

1. **DNS Resolution**: The bastion must be configured as the DNS server for the SNO node
2. **Gateway Access**: The gateway specified in `dhcp.router` must be reachable
3. **Network Interface**: The network interface name should match your environment (default: auto-detected)
4. **Static IP Assignment**: Ensure the SNO IP address is not used by other systems

### Troubleshooting Static IP Installation

#### Issue: Node cannot reach network
- Verify gateway IP is correct in configuration
- Check netmask matches your network subnet
- Ensure DNS server (bastion IP) is reachable

#### Issue: DNS resolution fails
- Verify dnsmasq is running: `systemctl status dnsmasq`
- Check DNS configuration: `dig @<bastion_ip> api.sno.cloud.lab`
- Review `/etc/dnsmasq.conf` for correct settings

#### Issue: PXE boot fails
- Verify TFTP is enabled in dnsmasq configuration
- Check TFTP files exist: `ls -la /var/lib/tftpboot/`
- Review GRUB configuration: `cat /var/lib/tftpboot/boot/grub2/grub.cfg`

#### Issue: Kernel parameters not applied
- Check GRUB configuration contains static IP parameters
- Verify network interface name matches your environment
- Review boot logs on the SNO node console

### Advantages of Static IP Mode

1. **No DHCP Required**: Works in environments where DHCP servers are restricted
2. **Predictable Networking**: Static configuration eliminates DHCP lease issues
3. **Security Compliance**: Meets requirements for environments that prohibit DHCP
4. **Simplified Troubleshooting**: Network configuration is explicit and visible in boot parameters

### Limitations

- Requires manual IP address management
- Network interface name must be known in advance (or use auto-detection)
- Changes to network configuration require regenerating boot files

