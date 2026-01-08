# 09 - PostgreSQL High Availability with CloudNativePG

## Overview
Deploying PostgreSQL with automatic failover using the CloudNativePG operator, providing production-grade high availability with minimal configuration.

## Why PostgreSQL HA?

Single-instance PostgreSQL (what we initially deployed) has limitations:
- Node failure = 2-3 minutes downtime
- Manual recovery required
- No read scaling
- Not production-ready for critical applications

**High Availability solves this:**
- Automatic failover (~5-10 seconds)
- Read replicas for scaling
- Zero manual intervention
- Production-grade reliability

## The Learning Journey: From Wrong to Right

### Phase 1: The StatefulSet Replica Mistake

**What I tried first:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
spec:
  replicas: 2  # ← Seems like HA, right?
```

**What actually happened:**
```
postgres-0: Separate database with own data
postgres-1: Separate database with own data
```

**The problem:** StatefulSet replicas without replication configuration creates **separate databases**, not replicas! Each pod has its own storage and no data synchronization.

```
User writes to postgres-0 → Data in Volume A
Service load-balances to postgres-1 → Data NOT there!
Result: Data inconsistency nightmare! ❌
```

**Key learning:** `replicas: 2` in a StatefulSet ≠ Database replication. You need:
- Streaming replication configured
- Primary/replica roles
- Replication slots
- Failover logic

This is complex to set up manually - that's where CloudNativePG comes in!

### Phase 2: The Right Way - CloudNativePG Operator

Instead of manually configuring PostgreSQL replication, use an **Operator** that handles all the complexity.

## What is CloudNativePG?

**CloudNativePG** is a Kubernetes operator for PostgreSQL that provides:
- Automatic Primary/Replica setup
- Streaming replication (automatic)
- Automatic failover and switchover
- Connection pooling
- Backup and recovery
- Monitoring integration

**Operator Pattern:**
You describe **what** you want (a PostgreSQL cluster), the operator figures out **how** to create it.

```yaml
# You write this:
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  instances: 2

# Operator creates:
- StatefulSet with replication configured
- Primary + Replica roles
- 3 Services (read-write, read-only, read)
- PVCs with Longhorn storage
- Replication management
- Failover monitoring
```

## Why CloudNativePG Over Alternatives?

**Considered alternatives:**
- **Manual replication:** Too complex, error-prone
- **Patroni:** Requires etcd, more moving parts
- **Crunchy Operator:** More enterprise features, more complex
- **Zalando Postgres Operator:** Good but CloudNativePG is more modern

**CloudNativePG advantages:**
- ✅ Modern, actively maintained
- ✅ Simple configuration
- ✅ Kubernetes-native
- ✅ Works perfectly with Longhorn
- ✅ Production-ready
- ✅ Great documentation

## Architecture Design Decisions

### Namespace Strategy

**Decision:** Separate `databases` namespace

```
demo-ha (Applications)
  └─ demo-app pods

databases (Data Layer)
  └─ postgres-ha cluster

cnpg-system (Infrastructure)
  └─ CloudNativePG operator

vault (Secrets Management)
  └─ Vault cluster
```

**Why separate namespaces:**
- Security: RBAC isolation
- Organization: Clear separation of concerns
- Maintenance: Update apps without touching databases
- Best Practice: Standard Kubernetes pattern

### Resource Sizing for 4GB Worker Nodes

**Cluster resources:**
- Control Plane: 8GB RAM
- Worker 1: 4GB RAM
- Worker 2: 4GB RAM

**PostgreSQL configuration for this constraint:**
```yaml
spec:+
  instances: 2  # Not 3 - fits in 4GB workers
  resources:
    requests:
      memory: "128Mi"  # Minimal but functional
      cpu: "100m"
    limits:
      memory: "256Mi"  # Prevents OOM on small nodes
      cpu: "500m"
```

**Why 2 instances instead of 3:**
- 1 Primary + 1 Replica = High Availability ✅
- Fits comfortably in 4GB worker nodes
- Still provides automatic failover
- Demonstrates HA concepts for portfolio
- In production with more RAM, would use 3+ instances

## Installation

### Step 1: Install CloudNativePG Operator

The operator runs cluster-wide and manages PostgreSQL clusters in any namespace.

```bash
# Add Helm repository
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

# Install operator in dedicated namespace
helm install cnpg \
  --namespace cnpg-system \
  --create-namespace \
  cnpg/cloudnative-pg

# Verify operator is running
kubectl get pods -n cnpg-system
```

**Expected output:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
cnpg-cloudnative-pg-xxxxxxxxx-xxxxx   1/1     Running   0          30s
```

**Why separate namespace for operator:**
- Operators are infrastructure, not workloads
- Cluster-wide permissions
- Updated independently
- Standard Kubernetes pattern

### Step 2: Create Database Namespace

```bash
kubectl create namespace databases
```

### Step 3: Create App User Secret

**Important:** Never commit passwords to Git!

```bash
kubectl create secret generic postgres-app-user \
  --from-literal=username=app \
  --from-literal=password='your-password' \
  -n databases
```

This secret is used by CloudNativePG to create the application database user.

### Step 4: Deploy PostgreSQL Cluster

Create `k8s/postgres/postgres-ha-cluster.yaml`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-ha
  namespace: databases
spec:
  instances: 2
  
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  
  bootstrap:
    initdb:
      database: demodb
      owner: app
      secret:
        name: postgres-app-user
  
  storage:
    storageClass: longhorn
    size: 5Gi
  
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "500m"
  
  affinity:
    podAntiAffinityType: preferred
    topologyKey: kubernetes.io/hostname
  
  monitoring:
    enablePodMonitor: true
  
  postgresql:
    parameters:
      shared_buffers: "64MB"
      effective_cache_size: "192MB"
      max_connections: "100"
    pg_hba:
      - host all all all scram-sha-256
```

**Configuration explained:**
- `instances: 2`: 1 Primary + 1 Replica
- `imageName`: PostgreSQL 16 from CloudNativePG
- `bootstrap.initdb`: Creates database and user on first start
- `storage`: Uses Longhorn with 5GB per instance
- `resources`: Sized for 4GB worker nodes
- `affinity`: Spreads pods across different nodes
- `monitoring.enablePodMonitor`: Exposes metrics for Prometheus
- `postgresql.parameters`: Optimized for small memory footprint

Deploy:
```bash
kubectl apply -f k8s/postgres/postgres-ha-cluster.yaml
```

### Step 5: Add Prometheus Monitoring

Create `k8s/postgres/podmonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: postgres-ha
  namespace: databases
  labels:
    app: postgres-ha
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: postgres-ha
  podMetricsEndpoints:
  - port: metrics
    interval: 30s
```

Deploy:
```bash
kubectl apply -f k8s/postgres/podmonitor.yaml
```

## Verification

### Check Cluster Status

```bash
# Check pods
kubectl get pods -n databases

# Expected output:
# NAME             READY   STATUS    RESTARTS   AGE
# postgres-ha-1    1/1     Running   0          2m
# postgres-ha-2    1/1     Running   0          1m

# Check cluster resource
kubectl get cluster -n databases

# Check detailed status
kubectl describe cluster postgres-ha -n databases
```

### Verify Primary and Replica Roles

```bash
# Check which pod is Primary
kubectl get pods -n databases -L role

# Or check cluster status
kubectl get cluster postgres-ha -n databases -o jsonpath='{.status.currentPrimary}'
```

### Check Services

CloudNativePG automatically creates three services:

```bash
kubectl get svc -n databases
```

**Output:**
```
NAME              TYPE        CLUSTER-IP      PORT(S)    AGE
postgres-ha-rw    ClusterIP   10.43.x.x       5432/TCP   2m
postgres-ha-ro    ClusterIP   10.43.x.x       5432/TCP   2m
postgres-ha-r     ClusterIP   10.43.x.x       5432/TCP   2m
```

**Service types:**
- `postgres-ha-rw` (Read-Write): Routes only to Primary
- `postgres-ha-ro` (Read-Only): Load-balanced across Replicas
- `postgres-ha-r` (Read): Load-balanced across all instances

### Check Storage

```bash
# Check PVCs
kubectl get pvc -n databases

# Expected: 2 PVCs, one per PostgreSQL instance
# NAME            STATUS   VOLUME        CAPACITY   STORAGECLASS
# postgres-ha-1   Bound    pvc-xxxxx     5Gi        longhorn
# postgres-ha-2   Bound    pvc-xxxxx     5Gi        longhorn
```

In Longhorn UI (`http://10.0.0.2:30880`):
- 2 volumes visible
- Each with 3 replicas (distributed across nodes)
- Total: 10GB usable, 30GB consumed with replication

### Test Database Connection

```bash
# Connect to Primary (read-write)
kubectl exec -it postgres-ha-1 -n databases -- psql -U app -d demodb

# In psql:
\dt              # List tables
\q               # Quit
```

## High Availability Testing

### Test 1: Simulate Primary Failure

**Goal:** Verify automatic failover works

```bash
# Identify which pod is Primary
kubectl get pods -n databases -L role

# Delete the Primary pod (e.g., postgres-ha-1)
kubectl delete pod postgres-ha-1 -n databases

# Watch failover happen
kubectl get pods -n databases -w
```

**What happens:**
1. Primary pod deleted (~1 second)
2. CloudNativePG detects failure (~5 seconds)
3. Replica (postgres-ha-2) promoted to Primary (~5 seconds)
4. Old Primary restarts and joins as new Replica (~30 seconds)

**Total downtime:** ~5-10 seconds

**Verification:**
```bash
# Check new Primary
kubectl get cluster postgres-ha -n databases -o jsonpath='{.status.currentPrimary}'

# Should now show postgres-ha-2 as Primary
```

### Test 2: Simulate Node Failure

**Goal:** Verify pod reschedules to healthy node with Longhorn storage

```bash
# Drain a worker node (simulates failure)
kubectl drain k3s-node-1 --ignore-daemonsets --delete-emptydir-data

# Watch pods reschedule
kubectl get pods -n databases -o wide -w

# Pods will move to k3s-node-2 or k3s-master
# Longhorn detaches volume from node-1, attaches to new node
# Data persists!
```

**Recovery:**
```bash
# Bring node back online
kubectl uncordin k3s-node-1
```

### Test 3: Verify Replication

```bash
# Write data to Primary
kubectl exec -it postgres-ha-1 -n databases -- psql -U app -d demodb -c "CREATE TABLE test (id SERIAL PRIMARY KEY, data TEXT);"
kubectl exec -it postgres-ha-1 -n databases -- psql -U app -d demodb -c "INSERT INTO test (data) VALUES ('test data');"

# Read from Replica (should see same data)
kubectl exec -it postgres-ha-2 -n databases -- psql -U app -d demodb -c "SELECT * FROM test;"

# Cleanup
kubectl exec -it postgres-ha-1 -n databases -- psql -U app -d demodb -c "DROP TABLE test;"
```

## Monitoring with Prometheus & Grafana

### Verify Metrics in Prometheus

Navigate to: `http://10.0.0.2:30090`

**Query examples:**
```promql
# Check if metrics are being scraped
up{job="postgres-ha"}

# PostgreSQL specific metrics
cnpg_backends_total
cnpg_pg_replication_lag_seconds
cnpg_pg_database_size_bytes
```

### Import Grafana Dashboard

Navigate to: `http://10.0.0.2:30030`

1. **+ (Plus Icon)** → **Import**
2. **Dashboard ID:** `20417`
3. **Load**
4. **Select Prometheus data source**
5. **Import**

**Dashboard shows:**
- Connection counts
- Replication lag
- Transaction rates
- Database size
- Query performance

## Storage Architecture

```
┌──────────────────────────────────────────┐
│  PostgreSQL HA Cluster                   │
│                                          │
│  ┌────────────┐      ┌────────────┐     │
│  │postgres-ha-1│     │postgres-ha-2│    │
│  │  (Primary) │ ══► │  (Replica)  │    │
│  └──────┬─────┘      └──────┬─────┘     │
│         │                   │           │
│         ▼                   ▼           │
│  ┌────────────┐      ┌────────────┐     │
│  │  PVC 5GB   │      │  PVC 5GB   │     │
│  │  Longhorn  │      │  Longhorn  │     │
│  └──────┬─────┘      └──────┬─────┘     │
└─────────┼────────────────────┼───────────┘
          │                    │
          ▼                    ▼
    ┌──────────────────────────────┐
    │   Longhorn Storage Layer     │
    │   3x Replication per Volume  │
    │                              │
    │  ┌─────┐  ┌─────┐  ┌─────┐  │
    │  │Node1│  │Node2│  │Node3│  │
    │  └─────┘  └─────┘  └─────┘  │
    └──────────────────────────────┘
```

**Data redundancy:**
- PostgreSQL replication: Primary → Replica (application level)
- Longhorn replication: 3x per volume (storage level)
- Total: Each database change is stored 6 times across the cluster!

## Connection Strings for Applications

**For writes (Primary only):**
```
postgres-ha-rw.databases.svc.cluster.local:5432
```

**For reads (load-balanced Replicas):**
```
postgres-ha-ro.databases.svc.cluster.local:5432
```

**For reads (all instances):**
```
postgres-ha-r.databases.svc.cluster.local:5432
```

**Full connection string example:**
```
postgresql://app:password@postgres-ha-rw.databases.svc.cluster.local:5432/demodb
```

## Configuration Options

### Scaling to More Replicas

Edit cluster and increase instances:
```yaml
spec:
  instances: 3  # Add one more replica
```

Apply:
```bash
kubectl apply -f k8s/postgres/postgres-ha-cluster.yaml
```

CloudNativePG will add a new replica automatically.

### Adjusting Resources

Edit resources in cluster spec:
```yaml
spec:
  resources:
    requests:
      memory: "256Mi"  # Increased
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "1000m"
```

Apply and restart:
```bash
kubectl apply -f k8s/postgres/postgres-ha-cluster.yaml
kubectl rollout restart cluster postgres-ha -n databases
```

### Changing PostgreSQL Parameters

Edit postgresql section:
```yaml
spec:
  postgresql:
    parameters:
      max_connections: "200"  # Increased from 100
      shared_buffers: "128MB"  # Increased from 64MB
```

Apply changes - CloudNativePG will perform a rolling restart.

## Troubleshooting

### Pods stuck in Pending

**Check:**
```bash
kubectl describe pod postgres-ha-1 -n databases
```

**Common causes:**
- PVC not bound (check Longhorn)
- Insufficient resources on nodes
- Node affinity preventing scheduling

### Replication lag

**Check lag:**
```bash
kubectl exec postgres-ha-1 -n databases -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

**Common causes:**
- Network issues between pods
- Replica overloaded
- Large transaction

### Failover not happening

**Check operator logs:**
```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

**Check cluster events:**
```bash
kubectl get events -n databases --sort-by='.lastTimestamp'
```

## Comparison: Single Instance vs HA

| Feature | Single Instance | CloudNativePG HA |
|---------|----------------|------------------|
| **Setup Complexity** | Low | Medium |
| **Instances** | 1 | 2+ (Primary + Replicas) |
| **Failover** | Manual (~2-3 min) | Automatic (~5-10 sec) |
| **Downtime on Node Failure** | 2-3 minutes | 5-10 seconds |
| **Read Scaling** | No | Yes (read replicas) |
| **Storage** | 5GB | 10GB (2 instances) |
| **Memory Usage** | ~256Mi | ~512Mi (2 pods) |
| **Production Ready** | Small apps only | Yes |
| **Operator Required** | No | Yes |

## What I Learned

- **StatefulSet replicas ≠ Database replication** - learned the hard way!
- **Operators abstract complexity** - one YAML instead of managing replication manually
- **Namespace design matters** - separate databases from applications
- **Resource constraints drive decisions** - 2 instances fit 4GB nodes, 3 would be tight
- **HA has overhead** - double the storage, more CPU/memory, but worth it
- **CloudNativePG is production-grade** - used by many companies

## Interview Talking Points

*"I initially tried using StatefulSet with replicas: 2, thinking this would provide high availability. I quickly learned this creates two separate databases without replication. I then implemented CloudNativePG operator which provides proper PostgreSQL streaming replication with automatic failover. The cluster has 1 Primary and 1 Replica, with Longhorn providing storage-level redundancy. Failover time is around 5-10 seconds, which is production-acceptable for most applications. I sized it for 2 instances instead of 3 due to 4GB RAM constraints on worker nodes, but this still demonstrates full HA capabilities."*

## Next Possible Steps

With PostgreSQL HA operational, you can now:
- **Vault Database Secrets Engine** - Dynamic credentials with automatic rotation
- **Demo app with database** - FastAPI connecting to PostgreSQL
- **Vault Agent Injector** - Automatically inject DB credentials into pods
- **Backup configuration** - CloudNativePG backups to S3/local storage
- **Connection pooling** - PgBouncer integration
- **Read/write splitting** - Route reads to replicas, writes to primary

The foundation is set for stateful, highly-available applications!