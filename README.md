# Kubernetes Homelab with GitOps Pipeline

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.33-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![K3s](https://img.shields.io/badge/K3s-Lightweight-FFC61C?logo=k3s&logoColor=black)](https://k3s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI/CD-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)

> Production-grade Kubernetes cluster with complete CI/CD pipeline, automated GitOps deployments, and comprehensive monitoring - built and documented from scratch on a Proxmox homelab.

## 📊 Project Highlights

- **Fully Automated Deployments** - Git push to production in ~5 minutes
- **High Availability** - 8-pod deployment with anti-affinity rules across worker nodes
- **Complete Observability** - Custom Prometheus metrics with Grafana dashboards
- **Self-Hosted Infrastructure** - Private registry, self-hosted CI/CD runner, all local
- **Production Patterns** - Rolling updates, health checks, resource limits, GitOps workflow

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Proxmox Homelab                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌────────────────────────────┐    ┌───────────────────────────┐   │
│   │    Kubernetes Cluster      │    │   LXC Container           │   │
│   │         (K3s)              │    │   (192.168.1.171)         │   │
│   │                            │    │                           │   │
│   │  ┌──────────────────────┐  │    │  ┌─────────────────────┐  │   │
│   │  │   Control Plane      │  │    │  │  Docker Registry    │  │   │
│   │  │   (10.0.0.2)         │  │    │  │  :5000              │  │   │
│   │  │                      │  │    │  └─────────────────────┘  │   │
│   │  │  - ArgoCD            │  │    │                           │   │
│   │  │  - Prometheus        │  │    │  ┌─────────────────────┐  │   │
│   │  │  - Grafana           │  │◄───┼──│  GitHub Actions     │  │   │
│   │  └──────────────────────┘  │    │  │  Runner             │  │   │
│   │                            │    │  └─────────────────────┘  │   │
│   │  ┌──────────────────────┐  │    │           │               │   │
│   │  │   Worker Nodes       │  │    └───────────┼───────────────┘   │
│   │  │   (10.0.0.3-4)       │  │                │                   │
│   │  │                      │  │                ▼                   │
│   │  │  - 8x demo-app pods  │  │          GitHub.com                │
│   │  └──────────────────────┘  │      (outbound only)               │
│   └────────────────────────────┘                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## ✨ Key Features

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
| [**00 - Project Overview**](docs/00-project-overview.md) | Complete architecture, network topology, and infrastructure reference |
| [**01 - Infrastructure Setup**](docs/01-infrastructure-setup.md) | Proxmox VMs, K3s cluster installation, initial testing |
| [**02 - Docker Registry**](docs/02-docker-registry.md) | Private registry setup and self-hosted GitHub Actions runner |
| [**03 - CI/CD Pipeline**](docs/03-github-actions-pipeline.md) | GitHub Actions workflow, image building, manifest updates |
| [**04 - GitOps with ArgoCD**](docs/04-argocd-gitops.md) | ArgoCD installation, application setup, automated deployments |
| [**05 - Monitoring Stack**](docs/05-monitoring-stack.md) | Prometheus & Grafana installation, custom metrics, dashboards |

## 🚀 Quick Start

### Prerequisites
- Proxmox VE host
- Basic understanding of Kubernetes concepts
- GitHub account

### Deployment Overview

1. **Set up infrastructure** - Create VMs from template, install K3s
2. **Configure registry** - Deploy private Docker registry
3. **Install GitOps** - Set up ArgoCD for automated deployments
4. **Deploy monitoring** - Install Prometheus & Grafana via Helm
5. **Configure CI/CD** - Set up GitHub Actions with self-hosted runner

Detailed instructions available in the [documentation](docs/).

## 📈 Metrics & Monitoring

### Cluster Resources
- **3 nodes** (1 control plane, 2 workers)
- **12 vCPUs** total across cluster
- **16GB RAM** total
- **300GB storage** across nodes

### Application Deployment
- **8 pod replicas** for high availability
- **Rolling updates** with max surge/unavailable of 1
- **Resource limits** enforced (128Mi memory, 200m CPU per pod)
- **Health probes** for liveness and readiness

### Monitoring Coverage
- **7 days** metric retention
- **30 second** scrape interval
- **Custom application metrics** via Prometheus instrumentation
- **Pre-built Grafana dashboards** for cluster and pods

## 🔧 Key Technical Decisions

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

- **Infrastructure as Code** - Managing entire infrastructure through Git
- **Kubernetes internals** - Pod scheduling, networking, storage, RBAC
- **CI/CD best practices** - Pipeline design, loop prevention, artifact management
- **Monitoring & Observability** - Metrics collection, visualization, alerting patterns
- **Problem-solving** - Debugging ServiceMonitor discovery, registry authentication, infinite loops
- **Production patterns** - High availability, rolling updates, health checks, resource management

## 📝 Notes

- This project uses example credentials and private network IPs from my homelab
- When replicating this setup, replace placeholder values with your own configuration
- All sensitive credentials are managed via GitHub Secrets in production workflows

## 🔗 Links

| Service | URL |
|---------|-----|
| **ArgoCD UI** | `https://10.0.0.2:30670` |
| **Prometheus** | `http://10.0.0.2:30090` |
| **Grafana** | `http://10.0.0.2:30030` |

---

**Built with** ☕ **and a lot of troubleshooting**