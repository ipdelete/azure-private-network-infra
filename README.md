# Azure Private Network Infrastructure

A secure Azure infrastructure deployment for hosting a Linux VM with NFS file share access, compl## 💻 Virtual Machine Configuration

- **Operating System**: Red Hat Enterprise Linux 9.4
- **VM Size**: Standard_B2s (2 vCPUs, 4 GB RAM)
- **Authentication**: SSH key-based (password disabled)
- **Network**: Private IP only (10.0.1.x/24)
- **Storage**: Premium SSD managed disk
- **Access**: Azure Bastion only (no public IP)
- **Cloud-Init**: Automated NFS mounting and aznfs installation
- **NFS Mount**: Automatically mounted at `/mount/{storageAccountName}/{nfsShareName}`olated from the internet with access only through Azure Bastion using SSH.

## ⚠️ Important: First Time Setup

**Before making any changes to this repository, run the git hooks setup:**

```bash
./scripts/setup-hooks.sh
```

This installs protective git hooks that prevent accidental commits of real SSH keys. The hooks ensure only the placeholder `YOUR_SSH_PUBLIC_KEY_HERE` can be committed to parameter files.

## 🏗️ Architecture Overview

This project creates a zero-trust network architecture with the following components:

- **Virtual Network**: Segmented subnets for different resource types
- **Storage Account**: Premium FileStorage with NFS 4.1 support
- **Private Endpoints**: Secure connectivity without internet exposure
- **Network Security Groups**: Granular traffic control
- **Azure Bastion**: Secure SSH access to VMs (planned)

## 🔒 Security Features

- ✅ **Zero Internet Access**: All resources are private with no public IPs (except Bastion)
- ✅ **Private Endpoints**: Storage access through private network only
- ✅ **Network Segmentation**: Dedicated subnets with security groups
- ✅ **Encrypted Storage**: HTTPS-only with TLS 1.2 minimum
- ✅ **Access Control**: SSH access only via Azure Bastion

## 📁 Project Structure

```
├── rg/                     # Resource Group deployment
│   ├── main.bicep         # Resource group Bicep template
│   ├── main.parameters.json
│   └── deploy.sh
├── vnet/                   # Virtual Network infrastructure
│   ├── main.bicep         # VNet, subnets, and NSGs
│   ├── main.parameters.json
│   └── deploy.sh
├── sa/                     # Storage Account with Private Endpoint
│   ├── main.bicep         # Storage account and private connectivity
│   ├── main.parameters.json
│   └── deploy.sh
├── nfs/                    # NFS File Share
│   ├── main.bicep         # NFS 4.1 share configuration
│   ├── main.parameters.json
│   └── deploy.sh
├── vm/                     # Linux Virtual Machine
│   ├── main.bicep         # Red Hat VM with cloud-init NFS mounting
│   ├── main.parameters.json
│   ├── deploy.sh
│   └── generate-ssh-key.sh # SSH key generation helper
├── bas/                    # Azure Bastion Host
│   ├── main.bicep         # Bastion host and public IP
│   ├── main.parameters.json
│   └── deploy.sh
├── scripts/                # Utility and setup scripts
│   ├── cleanup.sh         # Safe resource cleanup script
│   ├── get-rg.sh          # Quick status check utility
│   ├── pre-commit         # Git hook for SSH key protection
│   ├── setup-hooks.sh     # Git hooks installation script
│   └── README-hooks.md    # Git hooks documentation
└── README.md              # This file
```

## 🤖 Cloud-Init Automation

The VM deployment includes automated cloud-init configuration that:

### ✅ **Automated Setup Process**
1. **Repository Configuration**: Adds Microsoft package repository for RHEL 9
2. **Package Installation**: Installs `aznfs` package for optimized NFS 4.1 performance
3. **Directory Creation**: Creates mount point at `/mount/{storageAccountName}/{nfsShareName}`
4. **NFS Mounting**: Mounts the storage account NFS share with optimized settings
5. **Persistent Configuration**: Adds mount entry to `/etc/fstab` for automatic mounting on boot
6. **Permissions**: Sets proper ownership for the admin user

### 🔧 **Cloud-Init Script Features**
- **Network-aware**: Uses Azure environment functions for cross-cloud compatibility
- **Error-resilient**: Handles package installation and mounting gracefully
- **Performance-optimized**: Uses `nconnect=4` for enhanced throughput
- **Security-focused**: Uses proper NFS 4.1 security settings (`sec=sys`)

### 📋 **What Gets Installed**
```bash
# Packages installed via cloud-init:
- curl                    # For downloading Microsoft repository configuration
- rpm                     # For package management
- aznfs                   # Microsoft's optimized NFS client for Azure Files
```

### 🗂️ **File System Layout After Deployment**
```
/mount/
└── sapifile{uniqueString}/
    └── nfsshare/         # ← Your NFS share mounted here
        └── (your files)
```

## 🚀 Quick Start

### Prerequisites

- Azure CLI installed and authenticated
- Bicep CLI extension
- Appropriate Azure subscription permissions

### Deployment Steps

Deploy components in the following order:

1. **Create Resource Group**
   ```bash
   cd rg/
   ./deploy.sh
   ```

2. **Deploy Virtual Network**
   ```bash
   cd ../vnet/
   ./deploy.sh
   ```

3. **Create Storage Account**
   ```bash
   cd ../sa/
   ./deploy.sh
   ```

4. **Setup NFS Share**
   ```bash
   cd ../nfs/
   ./deploy.sh
   ```

5. **Deploy Linux VM**
   ```bash
   cd ../vm/
   # Generate SSH keys if needed
   ./generate-ssh-key.sh
   # Update main.parameters.json with your SSH public key
   ./deploy.sh
   ```

6. **Deploy Azure Bastion**
   ```bash
   cd ../bas/
   ./deploy.sh
   ```

## 🌐 Network Design

| Component | Subnet | Address Space | Purpose |
|-----------|--------|---------------|---------|
| VNet | - | `10.0.0.0/16` | Main virtual network |
| VM Subnet | vmSubnet | `10.0.1.0/24` | Linux VM placement |
| Bastion Subnet | AzureBastionSubnet | `10.0.2.0/24` | Azure Bastion host |
| Storage Subnet | storageSubnet | `10.0.3.0/24` | Private endpoints |

## 💾 Storage Configuration

- **Type**: Premium FileStorage account
- **Protocol**: NFS 4.1 (Linux-compatible)
- **Access**: Private endpoint only
- **Quota**: 100 GB (configurable)
- **Performance**: Premium tier for high IOPS

## � Virtual Machine Configuration

- **Operating System**: Red Hat Enterprise Linux 9.4
- **VM Size**: Standard_B2s (2 vCPUs, 4 GB RAM)
- **Authentication**: SSH key-based (password disabled)
- **Network**: Private IP only (10.0.1.x/24)
- **Storage**: Premium SSD managed disk
- **Access**: Azure Bastion only (no public IP)

## 🏰 Azure Bastion Configuration

- **SKU**: Basic (configurable to Standard)
- **Public IP**: Static Standard SKU (required for Bastion)
- **Access Method**: Azure Portal → VM → Connect → Bastion
- **Authentication**: SSH with private key
- **Security**: TLS-encrypted HTTPS connections

## �🔧 Configuration

### Resource Naming Convention

Resources use timestamp-based naming for uniqueness:
- Resource Group: `aet-pi-localdev-es2-tst3`
- Storage Account: `sa{timestamp}`
- VNet: `vnet-pi-localdev`

### Network Security Rules

- **VM Subnet**: SSH (22) from Bastion subnet only
- **Bastion Subnet**: Standard Azure Bastion communication rules
- **Storage Subnet**: Private endpoint traffic allowed

## 📊 Current Status

### ✅ Completed Components

- [x] Resource Group deployment
- [x] Virtual Network with subnet segmentation
- [x] Storage Account with private endpoint
- [x] NFS 4.1 file share creation
- [x] Network Security Groups
- [x] Private DNS zones
- [x] Red Hat Linux Virtual Machine with SSH access
- [x] Azure Bastion host for secure VM access
- [x] Cloud-init automated NFS mounting with aznfs

### 🚧 Planned Components

- [ ] Additional security hardening

## 🛠️ Management Scripts

| Script | Purpose |
|--------|---------|
| `scripts/cleanup.sh` | Safely delete all resources with confirmation |
| `scripts/get-rg.sh` | Quick status check of resource group |
| `scripts/setup-hooks.sh` | Install git hooks for SSH key protection |
| `*/deploy.sh` | Individual component deployment scripts |
| `vm/generate-ssh-key.sh` | Generate SSH key pair for VM access |

## 📝 Usage Examples

### Check Deployment Status
```bash
./scripts/get-rg.sh
```

### Clean Up Resources
```bash
./scripts/cleanup.sh
```

### Redeploy Single Component
```bash
cd vnet/
./deploy.sh
```

### Generate SSH Keys for VM
```bash
cd vm/
./generate-ssh-key.sh
# Copy the public key to main.parameters.json
```

### Access VM via Bastion
```bash
# Through Azure Portal:
# 1. Navigate to VM: vm-pi-localdev
# 2. Click "Connect" → "Bastion"
# 3. Use SSH authentication with private key
# 4. Username: azureuser
# 5. The NFS share will be automatically mounted at /mount/{storageAccountName}/{nfsShareName}
```

### Validate Cloud-Init and NFS Mount
```bash
# Connect to VM via Azure Portal → VM → Connect → Bastion
# Username: azureuser, use your SSH private key

# Check overall cloud-init status
sudo cloud-init status

# Check if cloud-init completed successfully
sudo cloud-init status --wait

# View cloud-init logs for troubleshooting
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# Verify NFS mount is active
df -h | grep nfs
mount | grep nfs

# Check fstab entry for persistent mounting
cat /etc/fstab | grep nfs

# Verify NFS share is accessible
ls -la /mount/sapifile*/nfsshare

# Test write access to NFS share
echo "Hello from VM" > /mount/sapifile*/nfsshare/test.txt
cat /mount/sapifile*/nfsshare/test.txt
```

### Check VM Status
```bash
az vm show --resource-group aet-pi-localdev-es2-tst3 --name vm-pi-localdev
```

## 🔍 Troubleshooting

### Common Issues

1. **Deployment Failures**: Check Azure CLI authentication and permissions
2. **Network Connectivity**: Verify NSG rules and private endpoint configuration
3. **Storage Access**: Ensure private DNS resolution is working
4. **Cloud-Init Failures**: Check cloud-init logs and status
5. **NFS Mount Issues**: Verify aznfs installation and network connectivity

### Cloud-Init and NFS Troubleshooting

```bash
# Connect to VM via Azure Portal → VM → Connect → Bastion

# Check cloud-init status and logs
sudo cloud-init status
sudo grep -i error /var/log/cloud-init.log
sudo grep -i failed /var/log/cloud-init.log

# Check if aznfs package is installed
rpm -qa | grep aznfs
yum list installed | grep aznfs

# Verify network connectivity to storage account
nslookup sapifile*.file.core.windows.net

# Check mount status
df -h | grep nfs
mount | grep nfs

# Manual mount test (if automated mount failed)
sudo mkdir -p /mnt/test
sudo mount -t aznfs sapifile*.file.core.windows.net:/sapifile*/nfsshare /mnt/test -o vers=4,minorversion=1,sec=sys,nconnect=4

# Check system logs for mount issues
sudo journalctl -u cloud-init
sudo dmesg | grep -i nfs
```

### Re-run Cloud-Init (if needed)

```bash
# Clean and re-run cloud-init (use with caution)
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules
```

### Validation Commands

```bash
# Check resource group status
az group show --name aet-pi-localdev-es2-tst3

# Verify VNet configuration
az network vnet show --resource-group aet-pi-localdev-es2-tst3 --name vnet-pi-localdev

# Check storage account private endpoint
az storage account show --name <storage-account-name> --resource-group aet-pi-localdev-es2-tst3

# Verify VM configuration and network settings
az vm show --resource-group aet-pi-localdev-es2-tst3 --name vm-pi-localdev --query "{Name:name, Size:hardwareProfile.vmSize, Status:provisioningState}"

# Check VM network interface (should have no public IP)
az network nic show --resource-group aet-pi-localdev-es2-tst3 --name vm-pi-localdev-nic --query "{PrivateIP:ipConfigurations[0].privateIPAddress, HasPublicIP:ipConfigurations[0].publicIPAddress!=null}"

# Check Bastion status
az network bastion show --resource-group aet-pi-localdev-es2-tst3 --name bastion-pi-localdev --query "{Name:name, State:provisioningState, Sku:sku.name}"
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test deployments in a separate subscription
4. Submit a pull request with detailed description

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 📞 Support

For issues or questions:
- Create an issue in this repository
- Review the Azure documentation for specific services
- Check Azure CLI and Bicep documentation

---

**Note**: This infrastructure is designed for development and testing purposes. For production deployments, consider additional security measures and compliance requirements.
