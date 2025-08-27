# Azure Private Network Infrastructure

A secure Azure infrastructure deployment for hosting a Linux VM with NFS file share access, completely isolated from the internet with access only through Azure Bastion using SSH.

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
│   ├── main.bicep         # Red Hat VM and network interface
│   ├── main.parameters.json
│   ├── deploy.sh
│   └── generate-ssh-key.sh # SSH key generation helper
├── scripts/                # Utility and setup scripts
│   ├── cleanup.sh         # Safe resource cleanup script
│   ├── get-rg.sh          # Quick status check utility
│   ├── pre-commit         # Git hook for SSH key protection
│   ├── setup-hooks.sh     # Git hooks installation script
│   └── README-hooks.md    # Git hooks documentation
└── README.md              # This file
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

### 🚧 Planned Components

- [ ] Azure Bastion host setup
- [ ] VM-to-NFS mount configuration
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

### Check VM Status
```bash
az vm show --resource-group aet-pi-localdev-es2-tst3 --name vm-pi-localdev
```

## 🔍 Troubleshooting

### Common Issues

1. **Deployment Failures**: Check Azure CLI authentication and permissions
2. **Network Connectivity**: Verify NSG rules and private endpoint configuration
3. **Storage Access**: Ensure private DNS resolution is working

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
