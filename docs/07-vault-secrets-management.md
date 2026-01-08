# 07 - Secrets Management with HashiCorp Vault

## Overview
Implementing HashiCorp Vault as the centralized secrets management solution for the Kubernetes cluster, providing secure storage, dynamic secrets generation, and fine-grained access control.

## Why Vault?

Before Vault, the cluster had no centralized secrets management:
- Database credentials hardcoded in deployments
- API keys stored as plain Kubernetes Secrets (base64, not encrypted at rest)
- No secret rotation
- No audit trail of who accessed what

**Vault solves this** by providing:
- Encrypted storage for secrets
- Dynamic secrets (credentials generated on-demand with TTL)
- Detailed audit logs
- Fine-grained access policies
- Automatic secret rotation

## Why Vault Over Alternatives?

**Vault is the industry standard** for Kubernetes secrets management:

**Alternatives considered:**
- **Sealed Secrets:** Only encrypts secrets in Git, not true secrets management
- **External Secrets Operator:** Syncs from external sources but isn't a secrets manager itself
- **Cloud Provider KMS:** Vendor lock-in, not applicable to on-prem homelab

**Vault provides:**
- Platform-agnostic (works on-prem, cloud, hybrid)
- Complete secrets lifecycle management
- Dynamic secrets for databases
- Industry-standard tool that appears in most DevOps/Platform Engineer job requirements

## Architecture

```
┌─────────────────────────────────────────────────┐
│           Vault Cluster (HA)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ vault-0  │  │ vault-1  │  │ vault-2  │       │
│  │ (Leader) │  │(Follower)│  │(Follower)│       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
│       │             │             │             │
│       └─────────────┴─────────────┘             │
│              Raft Consensus                     │
└─────────────────────────────────────────────────┘
                      │
                      │ Persistent Storage
                      ▼
┌─────────────────────────────────────────────────┐
│                Longhorn Storage                 │
│     3 PVCs (5GB each) with 3x replication       │
└─────────────────────────────────────────────────┘
```

## Vault Installation via Helm

### Helm Values Configuration

Created `k8s/vault.yaml` with production-ready settings:

```yaml
server:
  # High Availability with 3 Replicas
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      
      config: |
        ui = true
        
        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
        }
        
        storage "raft" {
          path = "/vault/data"
        }
        
        service_registration "kubernetes" {}

  # Persistent Storage with Longhorn
  dataStorage:
    enabled: true
    size: 5Gi
    storageClassName: longhorn
    accessMode: ReadWriteOnce

  # Service as NodePort (for UI access)
  service:
    type: NodePort
    nodePort: 30825

  # Resources
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m

# UI enablen
ui:
  enabled: true
  serviceType: NodePort
  serviceNodePort: 30820
```

**Key configuration choices:**

**Raft Storage Backend:**
- Integrated storage (no external database needed)
- Data replicated across all 3 Vault pods
- Automatic leader election
- Self-contained high availability

**TLS Disabled:**
- Simplified for homelab (HTTP instead of HTTPS)
- In production, would use cert-manager with Let's Encrypt
- Communication within cluster network is acceptable for learning environment

**NodePort 30820:**
- Direct UI access without port-forwarding
- Easy for development and demonstration

### Installation

```bash
# Create namespace
kubectl create namespace vault

# Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  -f k8s/vault.yaml

# Check pods
kubectl get pods -n vault
```

Expected output after installation:
```
NAME                                READY   STATUS    RESTARTS   AGE
vault-0                             0/1     Running   0          2m
vault-1                             0/1     Running   0          2m
vault-2                             0/1     Running   0          2m
vault-agent-injector-xxxxx          1/1     Running   0          2m
```

**Note:** Vault pods show `0/1 Ready` because they start in a **sealed** state. This is intentional security behavior.

## Understanding Vault's Sealed State

Vault always starts **sealed** (encrypted). This means:
- The encryption key is not in memory
- Vault cannot decrypt any secrets
- All API calls except unseal/status are blocked

**Why sealed by default?**
- Protects secrets if someone gains access to the storage backend
- Requires explicit human intervention (unseal keys) to access secrets
- Prevents automated attacks

**Unsealing** loads the encryption key into memory, allowing Vault to function.

## Initializing Vault

Vault must be initialized **once** to generate the master encryption key and unseal keys.

### Initialization via CLI

```bash
# Initialize vault-0 (only once, only on vault-0!)
kubectl exec -it vault-0 -n vault -- vault operator init > ~/vault-keys.txt
```

This generates and saves:
```
Unseal Key 1: <long-key>
Unseal Key 2: <long-key>
Unseal Key 3: <long-key>
Unseal Key 4: <long-key>
Unseal Key 5: <long-key>

Initial Root Token: s.<token>
```

**⚠️ CRITICAL:** These keys are shown **only once**. If lost, Vault is permanently locked.

**Shamir Secret Sharing:**
- 5 unseal keys generated
- Any 3 keys required to unseal
- Provides redundancy (can lose 2 keys and still unseal)
- In production, keys distributed to different people

**Storage:** Saved to `~/vault-keys.txt` on the master node. Should also be backed up to a secure location outside the cluster.

### Why Not Initialize via UI?

The UI initialization can sometimes not display the keys properly. CLI initialization guarantees the keys are captured.

## Building the Vault Cluster

After initialization, vault-0 is initialized but vault-1 and vault-2 need to join the Raft cluster.

### Unseal vault-0

```bash
# Extract the first 3 keys from vault-keys.txt
KEY1=$(grep "Unseal Key 1:" ~/vault-keys.txt | awk '{print $4}')
KEY2=$(grep "Unseal Key 2:" ~/vault-keys.txt | awk '{print $4}')
KEY3=$(grep "Unseal Key 3:" ~/vault-keys.txt | awk '{print $4}')

# Unseal vault-0
kubectl exec -it vault-0 -n vault -- vault operator unseal $KEY1
kubectl exec -it vault-0 -n vault -- vault operator unseal $KEY2
kubectl exec -it vault-0 -n vault -- vault operator unseal $KEY3
```

After the third unseal command, vault-0 status changes to:
```
Sealed: false
```

Pod becomes `1/1 Ready`.

### Join vault-1 and vault-2 to the Cluster

```bash
# vault-1 joins the Raft cluster
kubectl exec -it vault-1 -n vault -- vault operator raft join http://vault-0.vault-internal:8200

# vault-2 joins the Raft cluster
kubectl exec -it vault-2 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
```

Each should respond with:
```
Key       Value
---       -----
Joined    true
```

### Unseal vault-1 and vault-2

```bash
# Unseal vault-1 (same keys as vault-0!)
kubectl exec -it vault-1 -n vault -- vault operator unseal $KEY1
kubectl exec -it vault-1 -n vault -- vault operator unseal $KEY2
kubectl exec -it vault-1 -n vault -- vault operator unseal $KEY3

# Unseal vault-2
kubectl exec -it vault-2 -n vault -- vault operator unseal $KEY1
kubectl exec -it vault-2 -n vault -- vault operator unseal $KEY2
kubectl exec -it vault-2 -n vault -- vault operator unseal $KEY3
```

### Verify Cluster Status

```bash
# All pods should be 1/1 Ready
kubectl get pods -n vault

# Login with root token
ROOT_TOKEN=$(grep "Initial Root Token:" ~/vault-keys.txt | awk '{print $4}')
kubectl exec -it vault-0 -n vault -- vault login $ROOT_TOKEN

# Check Raft peer status
kubectl exec -it vault-0 -n vault -- vault operator raft list-peers
```

Expected output:
```
Node       Address                      State      Voter
----       -------                      -----      -----
vault-0    vault-0.vault-internal:8201  leader     true
vault-1    vault-1.vault-internal:8201  follower   true
vault-2    vault-2.vault-internal:8201  follower   true
```

✅ **Vault cluster is now operational with high availability!**

## Accessing the Vault UI

Navigate to: `http://10.0.0.2:30820`

**Login:**
- Method: **Token**
- Token: `<Initial Root Token from vault-keys.txt>`

The UI shows:
- **Secrets Engines:** Where secrets are stored
- **Access:** Authentication methods and policies
- **Policies:** Fine-grained access control rules
- **Tools:** Encryption, random data generation

## The Unsealing Challenge

**Every time a Vault pod restarts**, it must be manually unsealed:
- Pod crashes
- Node reboots
- Deployment updates
- Kubernetes evictions

This is intentional security - Vault won't auto-decrypt without human intervention.

### Manual Unseal Workflow

Created `~/unseal-vault.sh` for quick unsealing:

```bash
#!/bin/bash
# Vault Unseal Script

# Extract keys from vault-keys.txt
KEYS_FILE=~/vault-keys.txt
KEY1=$(grep "Unseal Key 1:" $KEYS_FILE | awk '{print $4}')
KEY2=$(grep "Unseal Key 2:" $KEYS_FILE | awk '{print $4}')
KEY3=$(grep "Unseal Key 3:" $KEYS_FILE | awk '{print $4}')

echo "🔓 Unsealing Vault pods..."

for pod in vault-0 vault-1 vault-2; do
  echo "Unsealing $pod..."
  kubectl exec -n vault $pod -- vault operator unseal $KEY1 >/dev/null 2>&1
  kubectl exec -n vault $pod -- vault operator unseal $KEY2 >/dev/null 2>&1
  kubectl exec -n vault $pod -- vault operator unseal $KEY3 >/dev/null 2>&1
  echo "✅ $pod unsealed"
done

echo "🎉 All Vault pods unsealed!"
kubectl get pods -n vault
```

Usage after cluster restart:
```bash
chmod +x ~/unseal-vault.sh
~/unseal-vault.sh
```

### Auto-Unseal in Production

In production environments, Vault supports **Auto-Unseal** using external Key Management Services:
- AWS KMS
- Azure Key Vault
- GCP Cloud KMS
- Transit Secret Engine (another Vault instance)


**Why not for homelab:**
- Requires cloud provider account
- Adds external dependency
- Manual unsealing is acceptable for learning environment
- Demonstrates understanding of the security model


## Storage Architecture

### Longhorn Integration

Check the PVCs created for Vault:

```bash
kubectl get pvc -n vault
```

Shows 3 PVCs:
```
NAME           STATUS   VOLUME                CAPACITY   STORAGECLASS
data-vault-0   Bound    pvc-xxxxx...          5Gi        longhorn
data-vault-1   Bound    pvc-xxxxx...          5Gi        longhorn
data-vault-2   Bound    pvc-xxxxx...          5Gi        longhorn
```

In Longhorn UI (`http://10.0.0.2:30880`):
- 3 Vault volumes visible
- Each with 3 replicas (data distributed across all nodes)
- Total: 15GB usable, 45GB consumed with replication

**Data flow:**
1. Secret written to Vault API
2. Vault encrypts with master key
3. Encrypted data written to Raft log
4. Raft replicates to all 3 pods
5. Each pod writes to its Longhorn volume
6. Longhorn replicates each volume across 3 nodes

**Result:** Secret is encrypted + replicated 9 times across the cluster!

## Security Model

**Vault's security layers:**

1. **Sealed State:** Encryption key not in memory by default
2. **Unseal Keys:** Required to decrypt master key (Shamir secret sharing)
3. **Root Token:** Full admin access (should be revoked after initial setup)
4. **Policies:** Fine-grained access control per path
5. **Audit Logging:** All access logged for compliance
6. **TLS (Production):** Encrypted communication (disabled in homelab)

**Homelab security:**
- Unseal keys stored outside cluster (on master node)
- Physical network isolation (homelab)
- Kubernetes RBAC limits pod access
- Root token stored securely

**Production security enhancements:**
- Auto-unseal with cloud KMS
- TLS everywhere
- Root token revoked after initial setup
- Unseal keys distributed to multiple people
- Hardware Security Module (HSM) integration
- Regular security audits

## What I Learned

- **Vault's security model:** Sealed state, Shamir secret sharing, encryption at rest
- **Raft consensus:** How distributed systems achieve consistency
- **High availability patterns:** Leader election, follower replication
- **Operational complexity:** Trade-off between security and convenience
- **Production vs homelab:** When to use cloud services vs self-hosted
- **Secrets management lifecycle:** Storage, rotation, auditing, revocation

## Common Issues and Solutions

**Issue: Pods stuck at 0/1 Ready**
- **Cause:** Vault is sealed (normal behavior)
- **Solution:** Unseal all pods with `~/unseal-vault.sh`

**Issue: vault-1 or vault-2 won't join cluster**
- **Cause:** Old Raft data in storage
- **Solution:** Delete PVC and pod, let it rejoin fresh
  ```bash
  kubectl delete pvc data-vault-2 -n vault
  kubectl delete pod vault-2 -n vault
  ```

**Issue: "Vault is not initialized" error on vault-1/vault-2**
- **Cause:** Only vault-0 should be initialized
- **Solution:** vault-1 and vault-2 join via `raft join`, not `operator init`

**Issue: Lost unseal keys**
- **Cause:** Did not save keys during initialization
- **Solution:** Vault is permanently locked - must delete all PVCs and reinitialize
  ```bash
  helm uninstall vault -n vault
  kubectl delete pvc -n vault --all
  # Reinstall and save keys this time!
  ```

## Verification Checklist

- ✅ All 3 Vault pods are `1/1 Ready`
- ✅ Raft cluster shows 1 leader + 2 followers
- ✅ Can login to UI with root token
- ✅ Longhorn shows 3 volumes with 3 replicas each
- ✅ Unseal script works after pod restart
- ✅ vault-keys.txt backed up securely

## Next Possible Steps

With Vault operational, the cluster now has enterprise-grade secrets management. Next phases:

1. **Kubernetes Authentication:** Allow pods to authenticate to Vault via service accounts
2. **Database Secrets Engine:** PostgreSQL with dynamic credentials
3. **Vault Agent Injector:** Automatically inject secrets into pods
4. **Demo Application:** FastAPI app that retrieves DB credentials from Vault at runtime
5. **GitOps Integration:** Vault secrets in ArgoCD deployments

This establishes the security foundation for all stateful applications in the cluster.
