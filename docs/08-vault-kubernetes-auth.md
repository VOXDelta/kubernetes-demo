# 08 - Vault Kubernetes Authentication

## Overview
Configuring Vault's Kubernetes authentication method to allow pods to securely authenticate and retrieve secrets without hardcoded credentials.

## Why Kubernetes Auth?

Without Kubernetes Auth, applications need to:
- Store Vault tokens in environment variables or files
- Manually rotate tokens
- Handle token renewal

**Kubernetes Auth solves this** by using Kubernetes Service Account tokens for authentication. Pods prove their identity to Vault using tokens that Kubernetes already manages.

## How It Works

```
Pod with ServiceAccount
    ↓ presents JWT token
Vault validates with Kubernetes API
    ↓ checks ServiceAccount + Namespace
Vault returns Vault token
    ↓ with assigned Policy
Pod can read authorized secrets
```

## Prerequisites

- Vault cluster running and unsealed
- Vault root token or admin access
- Pods running in Kubernetes

## Kubernetes Version Considerations

**Important:** Kubernetes 1.21+ changed the Service Account token format.

**K3s 1.33 (what we're running) requires:**
- `disable_iss_validation=true` in Vault config
- `audience` parameter in Vault role
- K3s uses `audience="k3s"` by default

This is **not** a security downgrade - it's adapting to the new token format.

## Step 1: Enable Kubernetes Auth Method

### Via CLI

```bash
# Exec into vault-0
kubectl exec -it vault-0 -n vault -- sh

# Set Vault address
export VAULT_ADDR='http://127.0.0.1:8200'

# Login with root token
vault login
# Enter your root token from vault-keys.txt

# Enable Kubernetes auth
vault auth enable kubernetes
```

**Output:**
```
Success! Enabled kubernetes auth method at: kubernetes/
```

### Via UI

Alternative: Use Vault UI at `http://10.0.0.2:30820`
1. Access → Enable new method
2. Select: Kubernetes
3. Path: `kubernetes` (default)
4. Enable Method

## Step 2: Configure Kubernetes Auth

Vault needs to know how to communicate with the Kubernetes API server.

```bash
# Still in vault-0 pod

vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token \
    disable_iss_validation=true
```

**What this does:**
- `kubernetes_host`: Vault learns the Kubernetes API endpoint
- `kubernetes_ca_cert`: CA cert to verify API server
- `token_reviewer_jwt`: Vault's own token to query Kubernetes API
- `disable_iss_validation=true`: Required for K8s 1.21+ token format

**Why these paths exist:**
Kubernetes automatically mounts Service Account credentials into every pod at `/var/run/secrets/kubernetes.io/serviceaccount/`. This includes:
- `token` - JWT for this pod's ServiceAccount
- `ca.crt` - Kubernetes CA certificate
- `namespace` - Current namespace

**Output:**
```
Success! Data written to: auth/kubernetes/config
```

## Step 3: Create Vault Policy

A policy defines which secrets a ServiceAccount can access.

```bash
# Still in vault-0 pod

vault policy write demo-app-policy - <<EOF
# Allow reading secrets under secret/demo-app/*
path "secret/data/demo-app/*" {
  capabilities = ["read", "list"]
}

# Allow reading database credentials (for later use)
path "database/creds/demo-app-role" {
  capabilities = ["read"]
}
EOF
```

**Policy explanation:**
- `path "secret/data/demo-app/*"`: Allows access to KV v2 secrets under this path
- `capabilities = ["read", "list"]`: Can read and list, but not create/update/delete
- Database path: Prepared for dynamic database credentials (next doc)

**Verify:**
```bash
vault policy read demo-app-policy
```

## Step 4: Create Kubernetes Role in Vault

The role connects Kubernetes ServiceAccounts to Vault policies.

```bash
# Still in vault-0 pod

vault write auth/kubernetes/role/demo-app \
    bound_service_account_names=demo-app \
    bound_service_account_namespaces=demo-ha \
    policies=demo-app-policy \
    audience="k3s" \
    ttl=1h
```

**Parameters:**
- `role/demo-app`: Name of this role
- `bound_service_account_names=demo-app`: Only pods with ServiceAccount "demo-app"
- `bound_service_account_namespaces=demo-ha`: Only in namespace "demo-ha"
- `policies=demo-app-policy`: Apply this policy to authenticated pods
- `audience="k3s"`: **K3s-specific!** K3s tokens have audience "k3s"
- `ttl=1h`: Vault token valid for 1 hour

**Output:**
```
Success! Data written to: auth/kubernetes/role/demo-app
```

### K3s Audience Discovery

If you see audience errors, check what your cluster uses:

```bash
# In a running pod:
kubectl exec <pod-name> -n <namespace> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | cut -d'.' -f2 | base64 -d 2>/dev/null | grep aud

# K3s output:
# "aud":["https://kubernetes.default.svc.cluster.local","k3s"]
```

K3s includes both the default K8s audience and `k3s`. We use `k3s` in the role configuration.

```bash
# Exit vault-0 pod
exit
```

## Step 5: Create ServiceAccount in Kubernetes

```bash
# Create ServiceAccount in demo-ha namespace
kubectl create serviceaccount demo-app -n demo-ha

# Verify
kubectl get serviceaccount demo-app -n demo-ha
```

## Step 6: Create Test Secret in Vault

```bash
# Exec back into vault-0
kubectl exec -it vault-0 -n vault -- sh

export VAULT_ADDR='http://127.0.0.1:8200'
vault login
# Enter root token

# Enable KV v2 secrets engine (if not already enabled)
vault secrets enable -path=secret kv-v2

# Create test secret
vault kv put secret/demo-app/config \
    api_key="your-key" \
    app_name="Demo Application"

# Verify
vault kv get secret/demo-app/config

exit
```

## Step 7: Test Authentication

Create a test pod with the ServiceAccount to verify everything works.

### Create Test Pod

```bash
kubectl run vault-test \
  --image=hashicorp/vault:latest \
  --overrides='{"spec":{"serviceAccountName":"demo-app"}}' \
  -n demo-ha \
  --command -- sh -c "sleep 3600"

# Wait for pod to be ready
kubectl wait --for=condition=ready pod vault-test -n demo-ha --timeout=60s
```

### Authenticate and Retrieve Secret

```bash
# Exec into test pod
kubectl exec -it vault-test -n demo-ha -- sh

# Set Vault address (internal Kubernetes service)
export VAULT_ADDR='http://vault.vault.svc.cluster.local:8200'

# Get Kubernetes token
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Authenticate to Vault
vault write auth/kubernetes/login \
    role=demo-app \
    jwt=$KUBE_TOKEN
```

**Expected output:**
```
Key                                       Value
---                                       -----
token                                     hvs.CAESXXXX...
token_accessor                            xxxxx
token_duration                            1h
token_renewable                           true
token_policies                            ["default" "demo-app-policy"]
identity_policies                         []
policies                                  ["default" "demo-app-policy"]
```

✅ **If you get a token, authentication works!**

### Read the Secret

```bash
# Set the Vault token from the previous output
export VAULT_TOKEN="hvs.CAESXXXX..."

# Read the secret
vault kv get secret/demo-app/config
```

**Expected output:**
```
====== Data ======
Key         Value
---         -----
api_key     your-key
app_name    Demo Application
```

✅ **Success! The pod can read secrets from Vault!**

### Cleanup Test Pod

```bash
exit  # Exit from test pod

kubectl delete pod vault-test -n demo-ha
```

## What We've Achieved

✅ Vault can authenticate Kubernetes pods
✅ Pods use ServiceAccount tokens (no hardcoded credentials)
✅ Fine-grained access control via policies
✅ Tokens have TTL and auto-expire
✅ Works with K3s 1.21+ token format

## Troubleshooting

### Error: "invalid audience (aud) claim"

**Problem:** Token audience doesn't match Vault role configuration.

**Solution:** 
1. Check token audience: `echo $KUBE_TOKEN | cut -d'.' -f2 | base64 -d | grep aud`
2. Update Vault role with correct audience: `audience="k3s"` for K3s

### Error: "permission denied"

**Problem:** Policy doesn't allow access to the secret path.

**Solution:**
- Verify policy: `vault policy read demo-app-policy`
- Ensure secret path matches policy path
- Remember KV v2 uses `secret/data/` prefix in paths

### Error: "service account not found"

**Problem:** ServiceAccount doesn't exist or wrong namespace.

**Solution:**
```bash
kubectl get serviceaccount demo-app -n demo-ha
```

If missing, create it: `kubectl create serviceaccount demo-app -n demo-ha`

### Vault can't reach Kubernetes API

**Problem:** Network connectivity or wrong API endpoint.

**Solution:**
```bash
# Check Vault config
vault read auth/kubernetes/config

# Verify Kubernetes API is accessible from Vault pod
kubectl exec -it vault-0 -n vault -- nc -zv $KUBERNETES_PORT_443_TCP_ADDR 443
```

## Security Considerations

**What we've secured:**
- ✅ No hardcoded Vault tokens in pods
- ✅ ServiceAccount-based authentication
- ✅ Namespace isolation (demo-ha only)
- ✅ Fine-grained policies (specific paths only)
- ✅ Token TTL (1 hour expiry)

**Production enhancements:**
- Enable Vault audit logging
- Use shorter TTL (15-30 minutes)
- Create separate policies per application
- Enable TLS for Vault communication
- Regular policy audits

## Architecture

```
┌─────────────────────────────────────────┐
│  Pod (demo-ha namespace)                │
│  ServiceAccount: demo-app               │
│  JWT Token: Auto-mounted by K8s        │
└──────────────┬──────────────────────────┘
               │
               │ 1. Login with JWT
               ▼
┌─────────────────────────────────────────┐
│  Vault                                  │
│  - Validates JWT with K8s API           │
│  - Checks ServiceAccount + Namespace    │
│  - Returns Vault token with policy      │
└──────────────┬──────────────────────────┘
               │
               │ 2. Read secrets with token
               ▼
┌─────────────────────────────────────────┐
│  Vault Secrets                          │
│  secret/demo-app/*                      │
│  (Allowed by demo-app-policy)           │
└─────────────────────────────────────────┘
```

## Next Possible Steps

With Kubernetes Auth working, you can now:
- **Deploy PostgreSQL** with Vault-managed credentials
- **Configure Vault Database Secrets Engine** for dynamic credentials
- **Use Vault Agent Injector** to automatically inject secrets into pods
- **Extend demo application** to retrieve database credentials from Vault

The foundation is set for secure, dynamic secrets management!