# 10 - Vault Database Secrets Engine for PostgreSQL

## Overview
Configuring Vault's Database Secrets Engine to generate dynamic, short-lived PostgreSQL credentials instead of static passwords.

## Why Dynamic Secrets?

**Problem with static credentials:**
- Password never changes
- Shared across all applications
- Manual rotation required
- No audit trail

**Solution with Vault:**
- Credentials generated on-demand
- Unique per request
- Auto-expire after 1 hour
- Automatic cleanup
- Full audit log

## How It Works

```
App → Vault → "Generate DB credentials"
      ↓
Vault → PostgreSQL → CREATE ROLE v-k8s-demo-app-XyZ123
      ↓
Vault → App → {username, password, lease: 1h}
      ↓
After 1h → Vault → PostgreSQL → DROP ROLE
```

**Key concepts:**
- **Root Credentials:** Vault uses `app` user to create/delete users
- **Role:** Template defining SQL statements and permissions
- **TTL:** Credentials expire automatically (1h default, 24h max)
- **Username format:** `v-k8s-demo-app-role-XyZ123-timestamp`

## Installation Steps

### Step 1: Enable Database Secrets Engine

```bash
kubectl exec -it vault-0 -n vault -- sh
export VAULT_ADDR='http://127.0.0.1:8200'
vault login  # Root token

vault secrets enable database
```

### Step 2: Configure PostgreSQL Connection

```bash
vault write database/config/postgres-ha \
    plugin_name=postgresql-database-plugin \
    allowed_roles="demo-app-role" \
    connection_url="postgresql://{{username}}:{{password}}@postgres-ha-rw.databases.svc.cluster.local:5432/demodb?sslmode=disable" \
    username="app" \
    password="your-password"
```

**Key points:**
- `postgres-ha-rw` - Primary only (writes required)
- Uses `app` user credentials
- `sslmode=disable` - OK for homelab, enable in production

### Step 3: Grant CREATEROLE Permission

The `app` user needs permission to create/delete database users.

```bash
kubectl exec -it postgres-ha-1 -n databases -- psql -U postgres -d demodb

ALTER ROLE app WITH CREATEROLE;
\du app  # Verify
\q
```

**Why needed:**
- CloudNativePG creates `app` as database owner, not with CREATEROLE
- Online docs often use `GRANT ALL` (overly permissive)
- We follow least privilege - only grant what's needed

**Security trade-off:**
- ✅ Vault can manage users dynamically
- ⚠️ `app` can create users (but not superuser)
- ✅ `app` credentials encrypted in Vault

### Step 4: Create Vault Role

Define SQL statements and permissions for dynamic users:

```bash
vault write database/roles/demo-app-role \
    db_name=postgres-ha \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT CONNECT ON DATABASE demodb TO \"{{name}}\"; \
        GRANT CREATE, USAGE ON SCHEMA public TO \"{{name}}\"; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```

**What this grants:**
- ✅ CRUD operations (SELECT, INSERT, UPDATE, DELETE)
- ✅ CREATE tables
- ✅ Use sequences (auto-increment)
- ❌ NO DROP DATABASE
- ❌ NO DROP SCHEMA
- ❌ NO SUPERUSER

**Why `CREATE, USAGE` on schema:**
PostgreSQL 15+ changed default permissions - explicit grant required.

**TTL:**
- `default_ttl="1h"` - Credentials expire after 1 hour
- `max_ttl="24h"` - Maximum renewal time

### Step 5: Generate Test Credentials

```bash
vault read database/creds/demo-app-role
```

**Output:**
```
Key                Value
---                -----
lease_id           database/creds/demo-app-role/abc123
lease_duration     1h
lease_renewable    true
password           A1b2C3d4E5f6G7h8I9j0
username           v-k8s-demo-app-role-YrPQw8t-1736347203
```

Vault just created a PostgreSQL user with these credentials!

### Step 6: Verify in PostgreSQL

```bash
exit  # Exit vault pod

kubectl exec -it postgres-ha-1 -n databases -- psql -h localhost -U app -d demodb
# Password: your-password!

\du
```

You should see the Vault-generated user with `Password valid until` timestamp.

```bash
\q
```

### Step 7: Test Dynamic User

```bash
kubectl exec -it postgres-ha-1 -n databases -- psql -h localhost -U v-k8s-demo-app-role-YrPQw8t-1736347203 -d demodb
# Use password from Vault output
```

**Test CRUD:**
```sql
CREATE TABLE vault_test (id SERIAL, data TEXT);
INSERT INTO vault_test (data) VALUES ('Dynamic credentials work!');
SELECT * FROM vault_test;
DROP TABLE vault_test;
\q
```

✅ **If this works, dynamic secrets are operational!**

## Troubleshooting

**Issue: "permission denied to create role"**
- Cause: `app` user missing CREATEROLE
- Solution: `ALTER ROLE app WITH CREATEROLE;`

**Issue: "permission denied for schema public"**
- Cause: PostgreSQL 15+ default permission changes
- Solution: Include `GRANT CREATE, USAGE ON SCHEMA public` in role

**Issue: "Peer authentication failed"**
- Cause: psql trying Unix socket instead of password auth
- Solution: Add `-h localhost` flag

## What We've Achieved

- Dynamic PostgreSQL credentials
- Short-lived users (1h TTL, auto-delete)
- Least privilege permissions (CRUD only, no DROP DATABASE)
- No hardcoded passwords
- Full audit trail

**Security improvement:**
- Before: One static password forever, shared, manual rotation
- After: Unique credentials per request, auto-expire, automatic cleanup

## What I Learned

- Dynamic secrets vs static passwords
- Vault Database Secrets Engine configuration
- Least privilege principle in practice
- Security trade-offs (convenience vs safety)

## Next Steps

With Vault Database Secrets Engine operational, several directions are possible:
- **Application Integration** - Deploy production workloads (e.g., Wiki.js) using Vault-managed credentials
- **Vault Agent Injector** - Automate secret injection into pods via sidecar containers
- **Backup & Recovery** - Implement CloudNativePG backups and disaster recovery procedures
- **Centralized Logging** - Add Loki for log aggregation across cluster
- **Service Mesh** - Deploy Istio or Linkerd for advanced traffic management and mTLS
- **CI/CD Extensions** - Integrate Vault into deployment pipelines for secure credential management