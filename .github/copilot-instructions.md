# Azure Private Network Infrastructure Project

## Project Overview
This project creates a secure Azure infrastructure for deploying a Linux VM with NFS file share access, completely isolated from the internet. Access to the VM is only possible through Azure Bastion using SSH.

## Architecture Goals
- **Zero Internet Access**: All resources are private with no public IPs (except Bastion)
- **Secure Access**: VM access only via Azure Bastion SSH
- **NFS Storage**: Private NFS file share mounted on the VM
- **Network Isolation**: Proper subnet segmentation with Network Security Groups

## Current Implementation Status

### ✅ Completed Components

#### 1. Resource Group (`rg/`)
- **Purpose**: Creates the foundational resource group for all resources
- **Scope**: Subscription-level deployment
- **Resource Group**: `aet-pi-localdev-es2-tst3`
- **Location**: `eastus2`
- **Files**:
  - [`rg/main.bicep`](../rg/main.bicep) - Bicep template for resource group creation
  - [`rg/main.parameters.json`](../rg/main.parameters.json) - Parameters file
  - [`rg/deploy.sh`](../rg/deploy.sh) - Deployment script

#### 2. Virtual Network Infrastructure (`vnet/`)
- **Purpose**: Creates the network foundation with proper segmentation
- **Scope**: Resource group-level deployment
- **Network Design**:
  - VNet: `10.0.0.0/16` (`vnet-pi-localdev`)
  - VM Subnet: `10.0.1.0/24` (for the Linux VM)
  - Bastion Subnet: `10.0.2.0/24` (`AzureBastionSubnet`)
  - Storage Subnet: `10.0.3.0/24` (for NFS private endpoint)
- **Security**: Network Security Groups configured for each subnet
- **Files**:
  - [`vnet/main.bicep`](../vnet/main.bicep) - VNet and subnet configuration
  - [`vnet/main.parameters.json`](../vnet/main.parameters.json) - Network parameters
  - [`vnet/deploy.sh`](../vnet/deploy.sh) - VNet deployment script

#### 3. Storage Account with Private Endpoint (`sa/`)
- **Purpose**: Creates a premium FileStorage account with NFS v4.1 support and private endpoint connectivity
- **Scope**: Resource group-level deployment
- **Storage Configuration**:
  - Kind: `FileStorage` (optimized for Azure Files with NFS support)
  - SKU: `Premium_LRS` (locally redundant premium storage)
  - Access Tier: `Hot` (for active workloads)
  - Network Access: `Deny` by default, allows specific IP (`76.204.100.248`) and Azure services
- **Private Connectivity**:
  - Private Endpoint: Deployed to `storageSubnet` for secure VNet access
  - Private DNS Zone: `privatelink.file.{environment().suffixes.storage}` for automatic DNS resolution
  - VNet Link: Connects private DNS zone to the virtual network
- **Security Features**:
  - HTTPS-only traffic enforcement
  - TLS 1.2 minimum version
  - Public blob access disabled
  - Shared key access enabled (required for some NFS scenarios)
- **Files**:
  - [`sa/main.bicep`](../sa/main.bicep) - Storage account, private endpoint, and DNS configuration
  - [`sa/main.parameters.json`](../sa/main.parameters.json) - Storage parameters
  - [`sa/deploy.sh`](../sa/deploy.sh) - Storage deployment script

#### 4. NFS File Share (`nfs/`)
- **Purpose**: Creates an NFS 4.1 file share on the storage account for secure file sharing with Linux VMs
- **Scope**: Resource group-level deployment
- **NFS Configuration**:
  - Protocol: `NFS 4.1` (Linux-compatible NFS protocol)
  - Root Squash: `NoRootSquash` (proper permissions for root access)
  - Access Tier: `Premium` (high-performance file operations)
  - Default Quota: `100 GB` (configurable)
- **Security Features**:
  - Private network access only (via storage account private endpoint)
  - No public internet access
  - Integrated with VNet private DNS resolution
- **Mount Information**:
  - Accessible from VMs in the same VNet
  - Standard NFS mount commands supported
  - Mount path provided in deployment outputs
- **Files**:
  - [`nfs/main.bicep`](../nfs/main.bicep) - NFS share configuration
  - [`nfs/main.parameters.json`](../nfs/main.parameters.json) - NFS parameters
  - [`nfs/deploy.sh`](../nfs/deploy.sh) - NFS deployment script

#### 5. Linux Virtual Machine (`vm/`)
- **Purpose**: Creates a Red Hat Enterprise Linux VM connected to the private network with no public IP and automated NFS mounting
- **Scope**: Resource group-level deployment
- **VM Configuration**:
  - OS: Red Hat Enterprise Linux 9.4 (latest)
  - Size: `Standard_B2s` (configurable)
  - Authentication: SSH key-based (no password authentication)
  - Admin User: `azureuser`
  - Storage: Premium LRS managed disk with ReadWrite caching
- **Cloud-Init Automation**:
  - Automated `aznfs` package installation for optimized NFS 4.1 performance
  - Automatic NFS share mounting at `/mount/{storageAccountName}/{nfsShareName}`
  - Persistent mounting configuration via `/etc/fstab`
  - Proper file ownership and permissions setup
  - Network-aware configuration using Azure environment functions
- **Network Configuration**:
  - Connected to `vmSubnet` (10.0.1.0/24)
  - Private IP allocation: Dynamic
  - No public IP address (zero internet access)
  - Protected by NSG allowing SSH from Bastion subnet only
- **Security Features**:
  - SSH key authentication only (password auth disabled)
  - VM Agent enabled for Azure extensions
  - No direct internet connectivity
  - Access only via Azure Bastion
- **NFS Integration**:
  - Storage account name dynamically resolved using same logic as storage deployment
  - Mount path: `/mount/{storageAccountPrefix}{uniqueString}/{nfsShareName}`
  - Optimized mount options: `vers=4,minorversion=1,sec=sys,nconnect=4`
  - Automatic recovery and persistent mounting across reboots
- **Files**:
  - [`vm/main.bicep`](../vm/main.bicep) - VM with cloud-init NFS mounting configuration
  - [`vm/main.parameters.json`](../vm/main.parameters.json) - VM and NFS parameters
  - [`vm/deploy.sh`](../vm/deploy.sh) - VM deployment script
  - [`vm/generate-ssh-key.sh`](../vm/generate-ssh-key.sh) - SSH key generation helper

#### 6. Azure Bastion Host (`bas/`)
- **Purpose**: Provides secure SSH access to the Linux VM without exposing it to the internet
- **Scope**: Resource group-level deployment
- **Bastion Configuration**:
  - SKU: `Basic` (configurable to Standard)
  - Location: `eastus2`
  - Public IP: Standard SKU static allocation (required for Bastion)
  - Subnet: Uses dedicated `AzureBastionSubnet` (10.0.2.0/24)
- **Network Configuration**:
  - Deployed to `AzureBastionSubnet` with proper NSG rules
  - Secure HTTPS-based SSH/RDP access
  - No direct VM public IP exposure required
- **Security Features**:
  - TLS-encrypted connections via HTTPS
  - Azure AD integration for access control
  - Session recording capabilities (Standard SKU)
  - Network isolation from internet
- **Access Method**:
  - Azure Portal: VM → Connect → Bastion
  - SSH authentication with private key
  - Username: `azureuser`
- **Files**:
  - [`bas/main.bicep`](../bas/main.bicep) - Bastion host and public IP configuration
  - [`bas/main.parameters.json`](../bas/main.parameters.json) - Bastion parameters
  - [`bas/deploy.sh`](../bas/deploy.sh) - Bastion deployment script

### 🔧 Utility Scripts
- [`scripts/cleanup.sh`](../scripts/cleanup.sh) - Safe resource group deletion with confirmation
- [`scripts/get-rg.sh`](../scripts/get-rg.sh) - Quick resource group status check
- [`scripts/remove-vm.sh`](../scripts/remove-vm.sh) - Safe VM removal while preserving other infrastructure

## Deployment Order
1. **Resource Group**: Run `rg/deploy.sh` to create the resource group
2. **Virtual Network**: Run `vnet/deploy.sh` to create network infrastructure
3. **Storage Account**: Run `sa/deploy.sh` to create storage account with private endpoint
4. **NFS File Share**: Run `nfs/deploy.sh` to create the NFS share on the storage account
5. **Linux Virtual Machine**: Run `vm/deploy.sh` to create the Red Hat VM with SSH access and automated NFS mounting
6. **Azure Bastion**: Run `bas/deploy.sh` to create the Bastion host for secure VM access

## Network Security Rules
The VNet deployment includes NSGs with initial rules:
- **VM Subnet**: Allows SSH from Bastion subnet only
- **Bastion Subnet**: Standard Azure Bastion rules
- **Storage Subnet**: Prepared for private endpoint access

## Cloud-Init Automation
The VM deployment includes automated cloud-init configuration that runs on first boot:

### Automated Setup Process
1. **Microsoft Repository**: Configures Microsoft package repository for RHEL 9
2. **Package Installation**: Downloads and installs `aznfs` package for optimized NFS 4.1 performance
3. **Directory Creation**: Creates mount point at `/mount/{storageAccountName}/{nfsShareName}`
4. **NFS Mounting**: Mounts the storage account NFS share with performance-optimized settings
5. **Persistent Configuration**: Adds mount entry to `/etc/fstab` for automatic mounting on reboot
6. **Permissions Setup**: Sets proper ownership for the admin user

### Cloud-Init Script Features
- **Base64 Encoded**: Script is encoded for secure parameter passing
- **Network Aware**: Uses Azure environment functions for cross-cloud compatibility
- **Performance Optimized**: Uses `nconnect=4` for enhanced NFS throughput
- **Security Focused**: Implements proper NFS 4.1 security settings (`sec=sys`)
- **Error Resilient**: Handles package installation and mounting gracefully

### Validation Commands
After VM deployment, users can validate the cloud-init setup:
```bash
# Check cloud-init status
sudo cloud-init status

# Verify NFS mount
df -h | grep nfs
ls -la /mount/sapifile*/nfsshare

# Check persistent mount configuration
cat /etc/fstab | grep nfs
```

## Planned Components (Not Yet Implemented)
- Additional NSG hardening rules

## Development Notes
- All deployments use timestamp-based unique names
- Resource group name is consistent across all components
- Bicep templates follow Azure best practices for security
- Scripts include proper error handling and logging