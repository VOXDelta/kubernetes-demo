# 00 - Project Overview

## System Architecture

This document provides a complete overview of the homelab infrastructure, including all components, network topology, and service mappings.

## Infrastructure Components

### Proxmox Host
**Platform:** Proxmox VE (Virtual Environment)
**Purpose:** Hypervisor hosting all VMs and LXC containers

### Kubernetes Cluster (K3s)

| Component | Hostname | IP Address | Role | Resources |
|-----------|----------|------------|------|-----------|
| Control Plane | k3s-master | 10.0.0.2 | API Server, Scheduler, Controller | 4 vCPU, 8GB RAM, 20GB Disk |
| Worker Node 1 | k3s-node-1 | 10.0.0.3 | Workload execution | 2 vCPU, 4GB RAM, 20GB Disk |
| Worker Node 2 | k3s-node-2 | 10.0.0.4 | Workload execution | 2 vCPU, 4GB RAM, 20GB Disk |

**OS:** Debian 13 (Trixie)
**Kubernetes Distribution:** K3s v1.33.6+k3s1
**Network:** Private network (10.0.0.0/24)

### Docker/CI Host (LXC Container)

| Component | IP Address | Purpose | Ports |
|-----------|------------|---------|-------|
| LXC Container | 192.168.1.171 | Docker Registry + GitHub Actions Runner | 5000 |

**Services Running:**
- Docker Registry (port 5000)
- GitHub Actions self-hosted runner
- Docker daemon

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                         Proxmox Host                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
        ▼                                           ▼
┌───────────────────┐                    ┌──────────────────────┐
│  K3s Network      │                    │  LXC Container       │
│  (10.0.0.0/24)    │                    │  (192.168.1.171)     │
│                   │                    │                      │
│  ┌─────────────┐  │                    │  ┌────────────────┐  │
│  │ k3s-master  │  │                    │  │ Docker Registry│  │
│  │ 10.0.0.2    │  │                    │  │ :5000          │  │
│  └─────────────┘  │                    │  └────────────────┘  │
│                   │                    │                      │
│  ┌─────────────┐  │                    │  ┌────────────────┐  │
│  │ k3s-node-1  │  │◄───────────────────┤  │ GitHub Actions │  │
│  │ 10.0.0.3    │  │   Pull images      │  │ Runner         │  │
│  └─────────────┘  │                    │  └────────────────┘  │
│                   │                    │                      │
│  ┌─────────────┐  │                    └──────────────────────┘
│  │ k3s-node-2  │  │                              │
│  │ 10.0.0.4    │  │                              │
│  └─────────────┘  │                              ▼
│                   │                         GitHub.com
└───────────────────┘                     (outbound connection)
```

## Service Ports

### Kubernetes Services (NodePort)

| Service | Port | Access URL | Purpose |
|---------|------|------------|---------|
| ArgoCD UI | 30670 | https://10.0.0.2:30670 | GitOps management interface |
| Prometheus | 30090 | http://10.0.0.2:30090 | Metrics collection UI |
| Grafana | 30030 | http://10.0.0.2:30030 | Monitoring dashboards |

### Kubernetes Internal Services

| Service | Port | Type | Purpose |
|---------|------|------|---------|
| demo-app | 80 → 8000 | ClusterIP | Demo application |
| kube-prometheus-stack-prometheus | 9090 | ClusterIP | Prometheus API |
| kube-prometheus-stack-grafana | 80 | ClusterIP | Grafana (internal) |

### External Services

| Service | IP:Port | Purpose |
|---------|---------|---------|
| Docker Registry | 192.168.1.171:5000 | Private container image storage |

## Data Flow

### CI/CD Pipeline Flow

```
┌──────────────┐
│ Developer    │
│ (git push)   │
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────┐
│ GitHub Repository                            │
│ (github.com/VOXDelta/kubernetes-demo)        │
└──────┬───────────────────────────────────────┘
       │
       │ Triggers
       ▼
┌──────────────────────────────────────────────┐
│ GitHub Actions Runner (192.168.1.171)        │
│ ┌──────────────────────────────────────────┐ │
│ │ 1. Checkout code                         │ │
│ │ 2. Build Docker image                    │ │
│ │ 3. Push to registry (192.168.1.171:5000) │ │
│ │ 4. Update k8s/deployment.yaml with SHA   │ │
│ │ 5. Commit & push to Git                  │ │
│ └──────────────────────────────────────────┘ │
└──────┬───────────────────────────────────────┘
       │
       │ Git commit
       ▼
┌──────────────────────────────────────────────┐
│ ArgoCD (running in K3s)                      │
│ - Polls Git every ~3 minutes                 │
│ - Detects deployment.yaml change             │
│ - Pulls new image from registry              │
│ - Applies to cluster                         │
└──────┬───────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────┐
│ Kubernetes Cluster                           │
│ - Rolling update with new image              │
│ - 8 pods across 2 worker nodes               │
└──────────────────────────────────────────────┘
```

### Monitoring Data Flow

```
┌──────────────────┐
│ Demo App Pods    │
│ (8 replicas)     │
│ /metrics:8000    │
└────────┬─────────┘
         │
         │ HTTP scrape every 30s
         ▼
┌──────────────────┐
│ Prometheus       │
│ (NodePort 30090) │
│ - Stores metrics │
│ - 7 day retention│
└────────┬─────────┘
         │
         │ PromQL queries
         ▼
┌──────────────────┐
│ Grafana          │
│ (NodePort 30030) │
│ - Dashboards     │
│ - Visualizations │
└──────────────────┘
```

## Application Deployment

### Demo App Configuration

**Namespace:** demo-ha
**Deployment:** demo-app
**Replicas:** 8 pods
**Image:** 192.168.1.171:5000/demo-ha/demo-app:sha-XXXXXXX

**Pod Distribution:**
- Anti-affinity rules spread pods across nodes
- Ensures high availability

**Resource Limits:**
```yaml
requests:
  memory: 64Mi
  cpu: 100m
limits:
  memory: 128Mi
  cpu: 200m
```

**Health Checks:**
- Liveness probe: /health endpoint
- Readiness probe: /health endpoint
- Initial delay: 10s / 5s respectively

## Namespaces

| Namespace | Purpose | Components |
|-----------|---------|------------|
| default | Default namespace | (unused in this setup) |
| demo-ha | Demo application | demo-app deployment, service, ingress, servicemonitor |
| argocd | GitOps controller | ArgoCD components |
| monitoring | Observability | Prometheus, Grafana, Alertmanager, exporters |
| kube-system | Kubernetes core | CoreDNS, metrics-server, traefik, local-path-provisioner |

## Storage

### Persistent Volumes

**Local Path Provisioner:**
- Default storage class in K3s
- Stores data on node local disk
- Used by: Prometheus, Grafana, ArgoCD

**Docker Registry Storage:**
- Location: LXC container at 192.168.1.171
- Path: ./volumes/registry-data
- Stores all container images

## Authentication & Security

### Docker Registry
- **Method:** HTTP Basic Auth (htpasswd)
- **Credentials:** Stored in GitHub Secrets
- **Access:** K3s nodes configured for insecure registry (HTTP)

### ArgoCD
- **Initial Admin Password:** Auto-generated, stored in secret
- **Repository Access:** SSH key-based (deploy key)
- **Git Connection:** Read-only access

### Grafana
- **Admin Password:** Set during Helm install
- **Access:** NodePort (internal network only)

### GitHub Actions
- **Runner Authentication:** Token-based registration
- **Secrets:** REGISTRY_USER, REGISTRY_PASSWORD
- **Connection:** Outbound to GitHub.com (no inbound required)

## Key Design Decisions

### Why Private Registry?
- Faster image pulls (no internet dependency)
- Complete data privacy
- No rate limits
- Learning opportunity

### Why Self-Hosted Runner?
- Direct access to private registry
- No firewall configuration needed
- Outbound-only connections
- Local network speed

### Why K3s?
- Lightweight Kubernetes distribution
- Perfect for homelab
- Production-ready features
- Easy installation

### Why 8 Replicas?
- Demonstrates high availability patterns
- Shows anti-affinity scheduling
- Testing rolling updates at scale
- Production-grade configuration (intentionally oversized for learning)

### Why GitOps?
- Single source of truth (Git)
- Automated deployments
- Easy rollbacks
- Audit trail

## Monitoring Metrics

### Cluster Metrics
- Node CPU, memory, disk, network usage
- Pod distribution and scheduling
- Cluster capacity utilization

### Application Metrics
- HTTP request rate per pod
- Response time (latency)
- Error rates (4xx, 5xx)
- Request/response sizes

### Kubernetes Metrics
- Deployment status
- Pod restarts and crashes
- Container resource usage vs limits

## Network Configuration

### K3s Nodes Registry Configuration
All K3s nodes (master + workers) are configured to allow insecure registry access:

**File:** `/etc/rancher/k3s/registries.yaml`
```yaml
mirrors:
  "192.168.1.171:5000":
    endpoint:
      - "http://192.168.1.171:5000"
```

### Kubernetes CNI
- **CNI Plugin:** Flannel (K3s default)
- **Network Mode:** VXLAN
- **Pod CIDR:** 10.42.0.0/16 (K3s default)
- **Service CIDR:** 10.43.0.0/16 (K3s default)

## Deployment Workflow

### Initial Deployment
1. Infrastructure setup (VMs, LXC)
2. K3s installation on all nodes
3. Docker registry setup
4. GitHub Actions runner installation
5. ArgoCD installation
6. Monitoring stack installation (Helm)
7. Application deployment via ArgoCD

### Continuous Deployment
1. Developer pushes code to GitHub
2. GitHub Actions runner builds image
3. Image pushed to private registry
4. deployment.yaml updated with new SHA
5. Change committed to Git (with `[skip ci]`)
6. ArgoCD detects change (~3 min)
7. ArgoCD triggers rolling update
8. Kubernetes updates pods (zero downtime)

## Future Enhancements

Potential additions to the infrastructure:

- **Logging:** Loki + Promtail for log aggregation
- **Tracing:** Jaeger or Tempo for distributed tracing
- **Secrets Management:** HashiCorp Vault or Sealed Secrets
- **Ingress Controller:** Production Traefik configuration with TLS
- **Service Mesh:** Istio or Linkerd for advanced traffic management
- **Backup Solution:** Velero for cluster backups
- **Cost Monitoring:** Kubecost for resource tracking
