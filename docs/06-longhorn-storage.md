# 06 - Distributed Block Storage with Longhorn

## Overview
Implementing Longhorn as distributed block storage across the K3s cluster to provide persistent, replicated storage for stateful applications like Vault and databases.

## Why Longhorn?

Before Longhorn, the cluster used K3s's default `local-path` provisioner:
- Storage only on the node where the pod runs
- No replication = data loss if node fails
- Pods can't move between nodes without losing data

**Longhorn solves this** by providing distributed block storage with automatic replication across all nodes.

## Prerequisites: VM Disk Expansion

The VMs started with 20GB disks, which wasn't enough for Longhorn's 3-way replication. Each VM needed expansion to 100GB.

### In Proxmox
Expanded each VM's disk from 20GB to 100GB through the Proxmox web UI.

### In the VMs
After Proxmox expanded the virtual disk, the filesystem inside each VM needed updating:

```bash
# On each VM (k3s-master, k3s-node-1, k3s-node-2)
# Expand the main partition
growpart /dev/vda 1

# Reboot to let kernel recognize new partition table
reboot

# After reboot: expand the filesystem
resize2fs /dev/vda1

# Verify
df -h /
```

**Important lesson learned:** Expanding disks while Longhorn is actively writing data can cause I/O errors. Always drain nodes or stop the workload first for maintenance operations.

## Longhorn Installation

### Install Prerequisites

Longhorn requires `open-iscsi` on all nodes for block storage operations:

```bash
# On all three nodes
sudo apt update
sudo apt install open-iscsi -y
sudo systemctl enable --now iscsid
sudo systemctl status iscsid
```

### Install via Helm

```bash
# Add Longhorn Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Create namespace
kubectl create namespace longhorn-system

# Install Longhorn with 3-way replication
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --set defaultSettings.defaultReplicaCount=3
```

Installation takes 2-3 minutes. Check status:

```bash
kubectl -n longhorn-system get pods
```

All pods should reach `Running` state (8-10 pods total).

## Accessing the Longhorn UI

Longhorn includes a web UI for monitoring and management.

### Expose via NodePort

```bash
kubectl -n longhorn-system patch svc longhorn-frontend -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "nodePort": 30880, "protocol": "TCP"}]}}'
```

Access at: `http://10.0.0.2:30880`

The UI shows:
- **Dashboard:** Total storage, usage across nodes
- **Volume:** All volumes with replica distribution
- **Node:** Available storage per node
- **Settings:** Backup configuration, storage overprovisioning

## Setting Longhorn as Default StorageClass

```bash
# Make Longhorn the default
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Disable local-path as default
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Verify
kubectl get storageclass
```

Expected output:
```
NAME                 PROVISIONER          
longhorn (default)   driver.longhorn.io
local-path          rancher.io/local-path
```

## Testing Longhorn Storage

### Create Test PVC

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
EOF
```

Check PVC status:
```bash
kubectl get pvc longhorn-test-pvc
# Should show STATUS: Bound
```

In the Longhorn UI, a new volume appears with 3 replicas distributed across the nodes.

### Test Pod with Persistent Storage

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-test
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:stable-alpine
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: longhorn-test-pvc
EOF
```

Write test data:
```bash
kubectl exec longhorn-test -- sh -c "echo 'Data written at $(date)' > /data/test.txt"
kubectl exec longhorn-test -- cat /data/test.txt
```

### Verify Persistence Across Pod Restarts

```bash
# Delete the pod
kubectl delete pod longhorn-test

# Recreate with same PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-test
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:stable-alpine
    command: ["sh", "-c", "cat /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: longhorn-test-pvc
EOF

# Check logs - should show original timestamp
kubectl logs longhorn-test
```

✅ If the original data is still there, Longhorn is working correctly!

### Cleanup

```bash
kubectl delete pod longhorn-test
kubectl delete pvc longhorn-test-pvc
```

## Migrating Monitoring Stack to Longhorn

The Prometheus/Grafana monitoring stack was initially using `local-path` storage. While we considered migrating to Longhorn for high availability, the decision was made to leave monitoring on `local-path` for now and focus on using Longhorn for more critical workloads like Vault and databases.

To migrate monitoring later, the process would be:
1. Uninstall the monitoring stack
2. Delete old PVCs
3. Reinstall with Longhorn StorageClass specified in Helm values

For critical infrastructure like Vault, Longhorn provides the high availability needed.

## How Longhorn Works

```
┌─────────────────────────────────────────────────┐
│  PersistentVolumeClaim (PVC)                    │
│  Request: 5Gi storage                           │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│  Longhorn Volume                                │
│  Automatically creates 3 replicas               │
└──────────────────┬──────────────────────────────┘
                   │
       ┌───────────┼───────────┐
       │           │           │
       ▼           ▼           ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Node 1   │ │ Node 2   │ │ Node 3   │
│ Replica  │ │ Replica  │ │ Replica  │
│ (5GB)    │ │ (5GB)    │ │ (5GB)    │
└──────────┘ └──────────┘ └──────────┘
```

**Key Features:**
- **Automatic Replication:** Data is replicated across nodes based on replica count
- **Self-Healing:** Failed replicas are automatically rebuilt
- **Node Failure Tolerance:** Volume remains accessible if nodes fail
- **Dynamic Provisioning:** Volumes created on-demand via PVCs

## Storage Capacity Planning

With 100GB per VM and 3-way replication:

**Example workload:**
- Vault: 5GB per pod × 3 pods = 15GB consumed (replicated = 45GB total)
- PostgreSQL: 10GB = 30GB total
- Monitoring (if migrated): 17GB = 51GB total

**Total capacity:** 3 nodes × 100GB = 300GB raw storage

**Effective capacity with 3x replication:** ~100GB usable

This is sufficient for the homelab use case. For larger deployments, VM disks can be expanded further.

## Longhorn vs Other Storage Solutions

**Longhorn:**
- ✅ Kubernetes-native
- ✅ Simple setup
- ✅ Good for block storage (PVCs)
- ✅ Excellent for homelab scale
- ❌ Block storage only (no S3/filesystem)

**Ceph:**
- ✅ Block + Object + Filesystem
- ✅ Massive scale (1000+ nodes)
- ❌ Complex setup and management
- ❌ Resource-intensive
- ❌ Overkill for 3-node homelab

**NFS (via TrueNAS):**
- ✅ Centralized management
- ✅ Large storage capacity
- ❌ Single point of failure
- ❌ Network dependency
- ❌ Less cloud-native

For a production-grade Kubernetes homelab demonstrating distributed systems, Longhorn is the right choice.

## What I Learned

- **Distributed storage concepts:** Replication, consistency, fault tolerance
- **Kubernetes storage primitives:** PV, PVC, StorageClass relationship
- **Operational considerations:** Node maintenance requires draining to avoid I/O issues
- **Resource planning:** 3x replication multiplies storage requirements
- **Production patterns:** How stateful workloads achieve high availability
- **Disk operations:** Expanding partitions on running systems requires care



## Next Possible Steps

With Longhorn providing distributed persistent storage, the cluster is ready for stateful workloads:
- HashiCorp Vault for secrets management
- PostgreSQL with Vault dynamic secrets
- Other databases requiring persistent storage

All critical data will now be replicated across nodes, providing the high availability needed for production-grade infrastructure.