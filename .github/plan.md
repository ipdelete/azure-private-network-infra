### 🧱 Step-by-Step Bicep Deployment Plan


#### **Step 1: Create the Virtual Network (VNet) and Subnets**
**Goal:** Establish the foundational network structure.

- VNet with address space (e.g., `10.0.0.0/16`)
- Subnets:
  - `vmSubnet` (e.g., `10.0.1.0/24`)
  - `AzureBastionSubnet` (must be named exactly)
  - `storageSubnet` (optional, for private endpoint)
- NSGs attached to each subnet (initially permissive for testing)

Status: complete

---

#### **Step 2: Deploy the Storage Account with NFS Enabled**
**Goal:** Provision secure file storage with NFS v4.1.

- Storage account type: `Premium_LRS`
- Enable NFS v4.1
- Disable public access
- Create a **private endpoint** in `storageSubnet`
- Link to a **Private DNS Zone** (`privatelink.file.core.windows.net`)

Status: in-progress

---

#### **Step 3: Deploy the Virtual Machine**
**Goal:** Launch a Linux VM with no public IP, ready to mount NFS.

- VM size and image (e.g., Ubuntu or CentOS)
- NIC in `vmSubnet`
- No public IP
- Optional: Managed Identity
- NSG rules to allow only Bastion and storage traffic

Status: complete

---

#### **Step 4: Deploy Azure Bastion**
**Goal:** Provide secure SSH access to the VM via portal.

- Bastion host in `AzureBastionSubnet`
- Public IP for Bastion only
- NSG rules to allow Bastion traffic

Status: new

---

#### **Step 5: Harden NSGs and Route Tables**
**Goal:** Lock down all inbound/outbound traffic except explicitly allowed flows.

- VM subnet: allow only Bastion inbound, storage outbound
- Storage subnet: allow only VM subnet inbound
- Bastion subnet: allow portal traffic only
- Optional: UDRs to block internet access

Status: new
