# PKI Key Vault — Bootstrap Procedure

This module deploys the private Key Vault used by `func-pki-ra` to fetch
step-ca secrets at runtime. Bicep alone cannot seed those secrets because:

1. The step-ca provisioner JWK + password live on `vm-pki-ca` (private VM).
2. The Key Vault has `publicNetworkAccess: 'Disabled'` and is reachable
   only from inside the PKI VNet.

The one-time bootstrap below populates three secrets the Function App
will read via Key Vault references:

| Secret name                     | Source                                              |
| ------------------------------- | --------------------------------------------------- |
| `step-ca-provisioner-password`  | `/etc/step-ca-password.txt` on `vm-pki-ca`          |
| `step-ca-provisioner-jwk`       | `provisioners[name=ra-provisioner].encryptedKey` (the JWE string that decrypts to the full private JWK) |
| `step-ca-root-cert`             | `/etc/step-ca/certs/root_ca.crt`                    |

## Pre-step (operational) — reissue step-ca TLS cert with SANs

The current step-ca HTTPS cert only has a CN; the Function App must
validate hostname against the SAN, so the cert must include both the IP
and the DNS name created by `pki-dns/`.

SSH via Bastion to `vm-pki-ca` as `azureuser`, then:

```bash
sudo -u step-ca step ca certificate ca.pki-lab.local \
  /etc/step-ca/certs/ssl_cert.pem \
  /etc/step-ca/secrets/ssl_cert_key.pem \
  --san ca.pki-lab.local \
  --san 10.1.1.4 \
  --provisioner admin --force

# Update ca.json to point at the new cert/key if needed (usually already correct)
sudo systemctl restart step-ca
sudo systemctl status step-ca --no-pager
```

Verify from a peer VM in the PKI VNet:

```bash
curl -v --cacert root_ca.crt https://ca.pki-lab.local/health
```

## Step 1 — Extract secrets from the CA VM

On `vm-pki-ca`:

```bash
# Provisioner password
sudo cat /etc/step-ca-password.txt > /tmp/step-ca-password.txt

# Encrypted JWK (JWE string) for the ra-provisioner — this is the
# `encryptedKey` field; it decrypts to the full private JWK with d/x/y.
sudo jq -r '.authority.provisioners[] | select(.name=="ra-provisioner") | .encryptedKey' \
  /etc/step-ca/config/ca.json > /tmp/step-ca-provisioner-jwk.txt

# Root cert (PEM)
sudo cp /etc/step-ca/certs/root_ca.crt /tmp/step-ca-root-cert.pem
```

Copy the three files to your jump box (e.g. via Bastion SSH `scp`).

## Step 2 — Grant yourself Secrets Officer on the new KV

```bash
KV_NAME=$(az deployment group show -g aet-pi-localdev-es2-tst4 \
  -n <pki-kv-deploy-name> --query properties.outputs.keyVaultName.value -o tsv)

MY_OID=$(az ad signed-in-user show --query id -o tsv)

az role assignment create \
  --assignee "$MY_OID" \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show -n "$KV_NAME" --query id -o tsv)
```

Because the vault has private-only access, run the seeding commands
from a VM inside the PKI VNet (the requester VM, or a temporary jump VM
peered/in-VNet), or use an `az` session with `--auth-mode login` from a
Bastion-tunneled session.

## Step 3 — Seed the secrets

```bash
az keyvault secret set --vault-name "$KV_NAME" \
  --name step-ca-provisioner-password \
  --file /tmp/step-ca-password.txt

az keyvault secret set --vault-name "$KV_NAME" \
  --name step-ca-provisioner-jwk \
  --file /tmp/step-ca-provisioner-jwk.txt

az keyvault secret set --vault-name "$KV_NAME" \
  --name step-ca-root-cert \
  --file /tmp/step-ca-root-cert.pem
```

## Step 4 — Clean up local copies

```bash
shred -u /tmp/step-ca-password.txt /tmp/step-ca-provisioner-jwk.txt /tmp/step-ca-root-cert.pem
```

## Root rotation procedure (future)

When the step-ca root is rotated:

1. Publish the new root PEM to KV: `az keyvault secret set --name step-ca-root-cert --file new-root.pem`.
2. Restart `func-pki-ra` so it reloads the trust root: `az functionapp restart -g <rg> -n func-pki-ra`.
3. Roll the step-ca server cert to chain from the new root.
4. Verify end-to-end: upload a test CSR, confirm a signed cert appears in `certs/`.

## Accepted lab risk

Encrypted JWK + decryption password live in the same vault scope, so
anyone with `Key Vault Secrets User` on this KV can mint OTTs. For
production, split into two vaults (or move the signing key into an
HSM-backed Managed HSM with a non-exportable key).
