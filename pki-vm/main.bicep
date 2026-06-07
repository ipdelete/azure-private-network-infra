targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 🏛️ PKI Lab — step-ca Certificate Authority VM
// ─────────────────────────────────────────────
// Deploys a Linux VM running step-ca as a private certificate authority.
// Cloud-init installs step-cli + step-ca from the official Smallstep repo,
// initializes the CA non-interactively, and starts it as a systemd service.

// 🔧 Parameters
param vmName string = 'vm-pki-ca'
param adminUsername string = 'azureuser'
param vmSize string = 'Standard_B2s'
param location string = resourceGroup().location
param vnetName string = 'vnet-pki-lab'
param subnetName string = 'caSubnet'

@secure()
@description('SSH public key for the admin user (ssh-rsa format)')
param adminPublicKey string

@description('CA name used in certificate subject')
param caName string = 'PKI Lab CA'

@description('step-ca provisioner name for the RA Function App')
param raProvisionerName string = 'ra-provisioner'

// 🔧 Variables
var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'

// Cloud-init script to install and bootstrap step-ca
var cloudInitTemplate = '''#cloud-config

# Add Smallstep yum repository (packages installed in runcmd for resilience)
yum_repos:
  smallstep:
    name: Smallstep
    baseurl: https://packages.smallstep.com/stable/fedora/
    enabled: true
    repo_gpgcheck: false
    gpgcheck: true
    gpgkey: https://packages.smallstep.com/keys/smallstep-0x889B19391F774443.gpg

runcmd:
  # Install packages — use a script block to handle retries and avoid YAML quoting issues
  - |
    for i in 1 2 3 4 5 6 7 8 9 10; do
      dnf install -y --disablerepo='rhel-*-eus-*' step-cli step-ca jq && break
      sleep 30
    done
    command -v step >/dev/null
    command -v step-ca >/dev/null
  - /usr/bin/step version
  - /usr/bin/step-ca version

  # Generate a random password for the CA keys
  - openssl rand -base64 32 > /etc/step-ca-password.txt
  - chmod 600 /etc/step-ca-password.txt

  # Get this VM's private IP for the CA DNS/address config
  - export CA_IP=$(hostname -I | awk '{print $1}')

  # Create step user home for CA state
  - mkdir -p /etc/step-ca
  - useradd --system --home /etc/step-ca --shell /bin/false step || true

  # Initialize the CA non-interactively
  - |
    STEPPATH=/etc/step-ca step ca init \
      --name "__CA_NAME__" \
      --dns "$CA_IP" \
      --dns "localhost" \
      --address ":443" \
      --provisioner "__RA_PROVISIONER_NAME__" \
      --password-file /etc/step-ca-password.txt \
      --deployment-type standalone

  # Fix ownership
  - chown -R step:step /etc/step-ca
  - chown step:step /etc/step-ca-password.txt

  # Create systemd unit for step-ca
  - |
    cat > /etc/systemd/system/step-ca.service <<'EOF'
    [Unit]
    Description=Smallstep Certificate Authority
    After=network-online.target
    Wants=network-online.target

    [Service]
    User=step
    Group=step
    ExecStart=/usr/bin/step-ca /etc/step-ca/config/ca.json --password-file /etc/step-ca-password.txt
    Restart=on-failure
    RestartSec=10
    AmbientCapabilities=CAP_NET_BIND_SERVICE

    [Install]
    WantedBy=multi-user.target
    EOF

  # Start step-ca
  - systemctl daemon-reload
  - systemctl enable --now step-ca

  # Export provisioner info for later retrieval
  - |
    STEPPATH=/etc/step-ca step ca provisioner list --admin-cert /etc/step-ca/certs/root_ca.crt \
      > /etc/step-ca/provisioners.json 2>/dev/null || true

  # Write the root CA fingerprint for easy bootstrap
  - |
    STEPPATH=/etc/step-ca step certificate fingerprint /etc/step-ca/certs/root_ca.crt \
      > /etc/step-ca/root-ca-fingerprint.txt 2>/dev/null || true
'''

var cloudInitScript = base64(replace(replace(cloudInitTemplate, '__CA_NAME__', caName), '__RA_PROVISIONER_NAME__', raProvisionerName))

// 🌐 Reference existing VNet and subnet
resource existingVNet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName

  resource caSubnet 'subnets' existing = {
    name: subnetName
  }
}

// 🌐 Network Interface Card
resource networkInterface 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: existingVNet::caSubnet.id
          }
        }
      }
    ]
  }
}

// 💻 step-ca Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: cloudInitScript
      linuxConfiguration: {
        disablePasswordAuthentication: true
        enableVMAgentPlatformUpdates: false
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'RedHat'
        offer: 'RHEL'
        sku: '9_4'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

// 📊 Outputs
output vmId string = virtualMachine.id
output vmName string = virtualMachine.name
output privateIPAddress string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
output networkInterfaceId string = networkInterface.id
