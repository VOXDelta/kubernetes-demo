# Kubernetes Homelab with GitOps Pipeline

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.33-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![K3s](https://img.shields.io/badge/K3s-Lightweight-FFC61C?logo=k3s&logoColor=black)](https://k3s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![HashiCorp Vault](https://img.shields.io/badge/Vault-Secrets-000000?logo=vault&logoColor=white)](https://www.vaultproject.io/)
[![Longhorn](https://img.shields.io/badge/Longhorn-Storage-48B4A1?logo=rancher&logoColor=white)](https://longhorn.io/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![CloudNativePG](https://img.shields.io/badge/CloudNativePG-HA-0066CC?logo=postgresql&logoColor=white)](https://cloudnative-pg.io/)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI/CD-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)

> Production-grade Kubernetes cluster with distributed storage, secrets management, complete CI/CD pipeline, automated GitOps deployments, and comprehensive monitoring - built and documented from scratch on a Proxmox homelab.

## 📊 Project Highlights

- **PostgreSQL High Availability** - CloudNativePG operator with automatic failover (~5-10 sec downtime)
- **Vault Kubernetes Authentication** - Pods authenticate to Vault using ServiceAccount tokens
- **Enterprise Secrets Management** - HashiCorp Vault with HA Raft storage for secure credential handling
- **Distributed Block Storage** - Longhorn with 3-way replication across cluster nodes
- **Fully Automated Deployments** - Git push to production in ~5 minutes
- **High Availability Everything** - 8-pod app deployment + 2-instance PostgreSQL + 3-pod Vault cluster
- **Complete Observability** - Custom Prometheus metrics with Grafana dashboards
- **Self-Hosted Infrastructure** - Private registry, self-hosted CI/CD runner, all local
- **Production Patterns** - Rolling updates, health checks, resource limits, GitOps workflow

## 🏗️ Architecture

```mermaid
flowchart LR
    %% Styling
    classDef external fill:#24292e,stroke:#fff,stroke-width:2px,color:#fff
    classDef infra fill:#0ea5e9,stroke:#fff,stroke-width:2px,color:#fff
    classDef control fill:#8b5cf6,stroke:#fff,stroke-width:2px,color:#fff
    classDef worker fill:#10b981,stroke:#fff,stroke-width:2px,color:#fff

    %% Nodes
    GH[GitHub]
    class GH external

    subgraph CICD[CI/CD Infrastructure]
        REG[Docker Registry]
        RUNNER[GitHub Runner]
    end
    class REG,RUNNER infra

    subgraph CLUSTER[K3s Cluster]
        subgraph CP[Control Plane]
            ARGO[ArgoCD]
            VAULT[Vault HA]
            MON[Prometheus<br/>Grafana]
        end
        
        subgraph WORKERS[Worker Nodes]
            APPS[Demo Apps<br/>8 Pods]
            STORAGE[Longhorn<br/>Storage]
        end
    end
    class ARGO,VAULT,MON control
    class APPS,STORAGE worker

    %% Flows
    GH -->|1. Push| RUNNER
    RUNNER -->|2. Build| REG
    RUNNER -.->|3. Update| GH
    GH -->|4. Sync| ARGO
    ARGO ==>|5. Deploy| APPS
    REG -.->|Pull| APPS
    APPS -.->|Metrics| MON
    VAULT -.->|Secrets| APPS
    APPS --> STORAGE
```

### Core Components

**External:** GitHub (source of truth)  
**CI/CD:** Docker Registry + Self-hosted GitHub Runner  
**Control Plane:** ArgoCD (GitOps), Vault (secrets), Prometheus/Grafana (monitoring)  
**Workers:** 8 FastAPI pods distributed across 2 nodes with Longhorn storage

### Pipeline Flow

1. **Push** code to GitHub
2. **Build** Docker image via self-hosted runner
3. **Update** deployment manifest with new image tag
4. **Sync** - ArgoCD detects changes every ~3 minutes
5. **Deploy** - Rolling update across worker nodes

### Infrastructure Details

| Component | Nodes | Description |
|-----------|-------|-------------|
| **K3s Cluster** | 3 nodes (1 control, 2 workers) | Lightweight Kubernetes distribution |
| **Longhorn** | Distributed storage | 3-way replication, ~100GB usable capacity |
| **Vault** | 3 pods (HA) | Secrets management with Raft consensus, Kubernetes auth |
| **PostgreSQL** | 2 instances (HA) | CloudNativePG operator, automatic failover |
| **Demo App** | 8 pods | FastAPI with Prometheus metrics |
| **Monitoring** | Prometheus + Grafana | 7-day metrics retention |
| **GitOps** | ArgoCD | Continuous deployment automation |

## ✨ Key Features

### PostgreSQL High Availability
- **CloudNativePG Operator** for automated PostgreSQL management
- **2 instances** (1 Primary + 1 Replica) with streaming replication
- **Automatic failover** (~5-10 seconds downtime)
- **3 Services** automatically created (read-write, read-only, read)
- **Longhorn storage** per instance with 3-way replication
- **Prometheus metrics** integration for monitoring

### Vault Kubernetes Authentication
- **ServiceAccount-based authentication** - pods authenticate without hardcoded tokens
- **K3s 1.21+ compatible** - configured for new token format
- **Fine-grained policies** - namespace and path-level access control
- **Token TTL** - automatic expiration for security
- **Ready for dynamic secrets** - foundation for database credential generation

### Secrets Management
- **HashiCorp Vault** in HA mode (3 pods with Raft consensus)
- Encrypted secrets storage with Shamir secret sharing
- Web UI for management and monitoring
- Persistent storage via Longhorn
- Kubernetes authentication configured

### Distributed Storage
- **Longhorn** distributed block storage
- 3-way replication across all cluster nodes
- Automatic volume provisioning via StorageClass
- Web UI for volume management and monitoring
- High availability for stateful workloads

### GitOps Workflow
- **ArgoCD** continuously monitors Git repository
- Automatic deployment on manifest changes
- Self-healing - cluster state always matches Git
- ~3 minute sync interval

### CI/CD Pipeline
- **GitHub Actions** with self-hosted runner
- Automated Docker builds on every commit
- SHA-based image tagging for traceability
- Automatic manifest updates
- Built-in loop prevention (`[skip ci]`)

### Infrastructure
- **3-node K3s cluster** on Proxmox VMs
- **Private Docker registry** for image storage
- **High availability** with pod anti-affinity
- **Zero-downtime deployments** via rolling updates

### Monitoring & Observability
- **Prometheus** for metrics collection (7-day retention)
- **Grafana** dashboards for visualization
- **Application metrics** via FastAPI Prometheus instrumentation
- **Pre-built dashboards** for cluster and application monitoring

## 🛠️ Tech Stack

### Infrastructure & Orchestration
![Proxmox](https://img.shields.io/badge/Proxmox-E57000?style=for-the-badge&logo=proxmox&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![K3s](https://img.shields.io/badge/K3s-FFC61C?style=for-the-badge&logo=k3s&logoColor=black)
![Debian](https://img.shields.io/badge/Debian_13-A81D33?style=for-the-badge&logo=debian&logoColor=white)

### Storage & Secrets
![Longhorn](https://img.shields.io/badge/Longhorn-48B4A1?style=for-the-badge&logo=rancher&logoColor=white)
![HashiCorp Vault](https://img.shields.io/badge/Vault-000000?style=for-the-badge&logo=vault&logoColor=white)

### Database & Operators
![PostgreSQL](https://img.shields.io/badge/PostgreSQL_16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![CloudNativePG](https://img.shields.io/badge/CloudNativePG-0066CC?style=for-the-badge&logo=postgresql&logoColor=white)

### CI/CD & GitOps
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)

### Monitoring & Observability
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)

### Application
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white)

### Tools
![Helm](https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=for-the-badge&logo=git&logoColor=white)

## 📚 Documentation

Complete step-by-step documentation covering the entire build process:

| Document | Description |
|----------|-------------|
| [**01 - Infrastructure Setup**](docs/01-infrastructure-setup.md) | Proxmox VMs, K3s cluster installation, initial testing |
| [**02 - Docker Registry**](docs/02-docker-registry.md) | Private registry setup and self-hosted GitHub Actions runner |
| [**03 - CI/CD Pipeline**](docs/03-github-actions-pipeline.md) | GitHub Actions workflow, image building, manifest updates |
| [**04 - GitOps with ArgoCD**](docs/04-argocd-gitops.md) | ArgoCD installation, application setup, automated deployments |
| [**05 - Monitoring Stack**](docs/05-monitoring-stack.md) | Prometheus & Grafana installation, custom metrics, dashboards |
| [**06 - Longhorn Storage**](docs/06-longhorn-storage.md) | Distributed block storage, replication, persistent volumes |
| [**07 - Vault Secrets Management**](docs/07-vault-secrets-management.md) | HashiCorp Vault HA setup, initialization, unsealing process |
| [**08 - Vault Kubernetes Auth**](docs/08-vault-kubernetes-auth.md) | Kubernetes authentication, policies, ServiceAccount integration |
| [**09 - PostgreSQL HA**](docs/09-postgres-ha-cloudnativepg.md) | CloudNativePG operator, HA cluster, automatic failover |

## 🚀 Quick Start

### Prerequisites
- Proxmox VE host
- Basic understanding of Kubernetes concepts
- GitHub account

### Deployment Overview

1. **Set up infrastructure** - Create VMs from template, install K3s
2. **Configure storage** - Deploy Longhorn for distributed persistent storage
3. **Configure registry** - Deploy private Docker registry
4. **Install secrets management** - Set up HashiCorp Vault in HA mode
5. **Configure Vault Kubernetes Auth** - Enable pod authentication to Vault
6. **Deploy PostgreSQL HA** - CloudNativePG operator with automatic failover
7. **Install GitOps** - Set up ArgoCD for automated deployments
8. **Deploy monitoring** - Install Prometheus & Grafana via Helm
9. **Configure CI/CD** - Set up GitHub Actions with self-hosted runner

Detailed instructions available in the [documentation](docs/).

## 📈 Metrics & Monitoring

### Cluster Resources
- **3 nodes** (1 control plane, 2 workers)
- **12 vCPUs** total across cluster
- **16GB RAM** total
- **300GB storage** across nodes (100GB per VM)

### Storage Architecture
- **Longhorn** distributed block storage
- **3-way replication** for high availability
- **~100GB usable capacity** with replication overhead
- **Automatic volume provisioning** via StorageClass

### Application Deployment
- **8 pod replicas** for high availability
- **Rolling updates** with max surge/unavailable of 1
- **Resource limits** enforced (128Mi memory, 200m CPU per pod)
- **Health probes** for liveness and readiness
- **Persistent storage** via Longhorn PVCs

### Secrets Management
- **Vault HA cluster** (3 pods with Raft storage)
- **15GB replicated storage** for Vault data
- **Shamir secret sharing** (5 keys, threshold 3)
- **Manual unsealing** workflow for security
- **Kubernetes Auth** configured for pod authentication

### Database Layer
- **PostgreSQL HA cluster** (2 instances with CloudNativePG)
- **Automatic failover** (~5-10 seconds downtime)
- **Streaming replication** between Primary and Replica
- **10GB replicated storage** (5GB per instance)
- **3 Services** for read-write, read-only, and read operations
- **Prometheus metrics** for monitoring

### Monitoring Coverage
- **7 days** metric retention
- **30 second** scrape interval
- **Custom application metrics** via Prometheus instrumentation
- **PostgreSQL metrics** via CloudNativePG PodMonitor
- **Pre-built Grafana dashboards** for cluster, apps, and database

## 🔧 Key Technical Decisions

### Why Longhorn?
Provides Kubernetes-native distributed block storage with automatic replication, perfect for homelab scale while demonstrating production patterns. Simpler than Ceph but more robust than NFS.

### Why Vault?
Industry-standard secrets management that demonstrates enterprise-grade security practices. Vault's dynamic secrets and audit logging are critical for production Kubernetes deployments.

### Why K3s?
Lightweight Kubernetes distribution perfect for homelab environments while maintaining production-grade features.

### Why Private Registry?
- Faster image pulls (no internet dependency)
- Complete control over images
- No rate limits
- Privacy for development

### Why Self-Hosted Runner?
- Direct access to private registry
- No firewall configuration needed
- Outbound-only connections for security
- Local network speeds

### Why GitOps?
- Git as single source of truth
- Automated deployments with audit trail
- Easy rollbacks
- Configuration drift prevention

## 🎓 What I Learned

- **PostgreSQL High Availability** - Operator pattern vs manual replication, failover mechanisms
- **CloudNativePG Operator** - How operators abstract complexity and manage stateful workloads
- **Kubernetes Operators** - Custom Resource Definitions (CRDs) and operator lifecycle
- **Vault Kubernetes Auth** - ServiceAccount tokens, audience claims, K3s-specific configuration
- **Namespace Design** - Separating applications, databases, and infrastructure layers
- **StatefulSet vs Replication** - Why `replicas: 2` doesn't equal database replication
- **Distributed Systems** - Raft consensus, leader election, replica management
- **Secrets Management** - Vault's security model, unsealing process, HA patterns
- **Storage Architecture** - Persistent volumes, storage classes, replication strategies
- **Infrastructure as Code** - Managing entire infrastructure through Git
- **Kubernetes Internals** - Pod scheduling, networking, storage, RBAC
- **CI/CD Best Practices** - Pipeline design, loop prevention, artifact management
- **Monitoring & Observability** - Metrics collection, visualization, alerting patterns
- **Problem-Solving** - Disk I/O errors, ServiceMonitor discovery, audience errors, registry authentication
- **Production Patterns** - High availability, rolling updates, health checks, resource management
- **Resource Constraints** - Sizing workloads for limited hardware (4GB worker nodes)

## 📝 Notes

- This project uses example credentials and private network IPs from my homelab
- When replicating this setup, replace placeholder values with your own configuration
- All sensitive credentials are managed via GitHub Secrets in production workflows
- Vault unseal keys are stored securely outside the cluster

## 🔗 Links

| Service | URL |
|---------|-----|
| **ArgoCD UI** | `https://10.0.0.2:30670` |
| **Prometheus** | `http://10.0.0.2:30090` |
| **Grafana** | `http://10.0.0.2:30030` |
| **Vault UI** | `http://10.0.0.2:30820` |
| **Longhorn UI** | `http://10.0.0.2:30880` |

## 🚧 Next Possible Steps

From here, the infrastructure can be extended in multiple directions:
- **Vault Database Secrets Engine** - Dynamic PostgreSQL credentials with automatic rotation
- **Vault Agent Injector** - Automatically inject secrets into pods at runtime
- **Demo App with Database** - Extend FastAPI app with PostgreSQL integration and Vault-managed credentials
- **Backup Strategy** - CloudNativePG backups to S3 or Longhorn snapshots to TrueNAS
- **Logging Stack** - Add Loki for centralized log aggregation
- **Service Mesh** - Istio or Linkerd for advanced traffic management
- **Multi-Environment** - Separate dev/staging/prod namespaces with ArgoCD
- **TLS Everywhere** - cert-manager with Let's Encrypt for all services
- **Network Policies** - Restrict pod-to-pod communication

---

**Built with** ☕ **and a lot of troubleshooting**