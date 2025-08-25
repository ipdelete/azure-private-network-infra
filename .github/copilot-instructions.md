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
  - [`rg/main.bicep`](rg/main.bicep) - Bicep template for resource group creation
  - [`rg/main.parameters.json`](rg/main.parameters.json) - Parameters file
  - [`rg/deploy.sh`](rg/deploy.sh) - Deployment script

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
  - [`vnet/main.bicep`](vnet/main.bicep) - VNet and subnet configuration
  - [`vnet/main.parameters.json`](vnet/main.parameters.json) - Network parameters
  - [`vnet/deploy.sh`](vnet/deploy.sh) - VNet deployment script

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
  - [`sa/main.bicep`](sa/main.bicep) - Storage account, private endpoint, and DNS configuration
  - [`sa/main.parameters.json`](sa/main.parameters.json) - Storage parameters
  - [`sa/deploy.sh`](sa/deploy.sh) - Storage deployment script

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
  - [`nfs/main.bicep`](nfs/main.bicep) - NFS share configuration
  - [`nfs/main.parameters.json`](nfs/main.parameters.json) - NFS parameters
  - [`nfs/deploy.sh`](nfs/deploy.sh) - NFS deployment script

### 🔧 Utility Scripts
- [`cleanup.sh`](cleanup.sh) - Safe resource group deletion with confirmation
- [`get-rg.sh`](get-rg.sh) - Quick resource group status check

## Deployment Order
1. **Resource Group**: Run `rg/deploy.sh` to create the resource group
2. **Virtual Network**: Run `vnet/deploy.sh` to create network infrastructure
3. **Storage Account**: Run `sa/deploy.sh` to create storage account with private endpoint
4. **NFS File Share**: Run `nfs/deploy.sh` to create the NFS share on the storage account

## Network Security Rules
The VNet deployment includes NSGs with initial rules:
- **VM Subnet**: Allows SSH from Bastion subnet only
- **Bastion Subnet**: Standard Azure Bastion rules
- **Storage Subnet**: Prepared for private endpoint access

## Planned Components (Not Yet Implemented)
- Linux Virtual Machine with no public IP
- Azure Bastion host for secure access
- Additional NSG hardening rules

## Development Notes
- All deployments use timestamp-based unique names
- Resource group name is consistent across all components
- Bicep templates follow Azure best practices for security
- Scripts include proper error handling and logging