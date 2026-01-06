# 05 - Monitoring with Prometheus & Grafana

## Overview
Implementing comprehensive monitoring and observability for both the Kubernetes cluster infrastructure and application metrics using Prometheus and Grafana.

## Why Monitoring?

Without monitoring, you're flying blind:
- Can't see resource usage (CPU, memory, network)
- No visibility into application performance
- Can't detect issues before they become critical
- No data for capacity planning

For a production-grade setup, monitoring is essential - even in a homelab.

## Prerequisites: Installing Helm

Helm is the package manager for Kubernetes - it simplifies deploying complex applications.
```bash
# Download and install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

## Installing the Monitoring Stack

I used the `kube-prometheus-stack` Helm chart, which bundles:
- **Prometheus** - metric collection and storage
- **Grafana** - visualization and dashboards
- **Alertmanager** - alert routing and notification
- **Node Exporter** - node-level metrics
- **Kube State Metrics** - Kubernetes object metrics

### Installation Steps
```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack with custom configuration
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=7d \
  --set grafana.adminPassword=admin123 \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090 \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30030
```

**Configuration explained:**
- `retention=7d` - Keep metrics for 7 days (adjust based on storage)
- `grafana.adminPassword` - Set Grafana admin password (change in production!)
- `NodePort` services - Exposes Prometheus (30090) and Grafana (30030) for easy access
- No need for port-forwarding with NodePort

### Verify Installation
```bash
kubectl get pods -n monitoring

# You should see:
# - alertmanager
# - grafana
# - prometheus
# - kube-state-metrics
# - node-exporter (one per node)
# - prometheus-operator
```

All pods should show "Running" status after ~2 minutes.

## Accessing the UIs

With NodePort configuration, both UIs are directly accessible:

**Prometheus:** `http://10.0.0.2:30090`
**Grafana:** `http://10.0.0.2:30030`

**Grafana Login:**
- Username: `admin`
- Password: `admin123` (as configured during install)

## Application Metrics

To get custom metrics from my FastAPI demo app, I needed to expose a `/metrics` endpoint.

### Adding Prometheus to the App

Updated `app/requirements.txt`:
```
fastapi
uvicorn
prometheus-fastapi-instrumentator
```

Updated `app/main.py`:
```python
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()

# Enable Prometheus metrics
Instrumentator().instrument(app).expose(app)

# Your routes here...
```

This automatically creates a `/metrics` endpoint with:
- HTTP request count
- Request duration
- Request size
- Response size

### ServiceMonitor Configuration

To tell Prometheus to scrape my app's metrics, I created a ServiceMonitor:
```yaml
# k8s/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-app
  namespace: demo-ha
  labels:
    app: demo-app
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: demo-app
  endpoints:
  - port: http
    interval: 30s
    path: /metrics
```

**Initial issue:** Prometheus wasn't scraping my app. **Solution:** Added the `port: http` field to match the service port name. Also ensured the `release: kube-prometheus-stack` label was present.


### Verifying Metrics Collection

Check if Prometheus is scraping your app:

1. Open Prometheus UI: `http://10.0.0.2:30090`
2. Go to Status → Targets
3. Search for "demo-app" - should show "UP" status for all pods

You can also query metrics directly in the Prometheus query interface:
- `http_requests_total` - total HTTP requests
- `http_request_duration_seconds` - request latency
- `up{job="demo-app"}` - pod health status

## Grafana Dashboards

The kube-prometheus-stack comes with excellent pre-configured dashboards that work out of the box.

### Accessing Dashboards

1. Open Grafana: `http://10.0.0.2:30030`
2. Login with admin/admin123
3. Navigate to Dashboards → Browse


### Pre-built Dashboards

**Cluster Monitoring:**
- **Kubernetes / Compute Resources / Cluster** - Overall cluster resource usage
- **Kubernetes / Compute Resources / Namespace (Pods)** - Per-namespace breakdown
- **Kubernetes / Compute Resources / Node (Pods)** - Per-node resource usage

**Application Monitoring:**
- **Kubernetes / Compute Resources / Pod** - Individual pod metrics (CPU, memory, network)

**Node Monitoring:**
- **Node Exporter / Nodes** - Detailed node metrics (disk I/O, network, CPU, memory)

These dashboards provide incredible visibility into:
- Resource utilization (CPU, memory, disk, network)
- Pod distribution across nodes
- Container restarts and crashes
- Network traffic patterns
- Request rates and latencies

## What You Can Monitor

With this setup, you get comprehensive metrics for:

**Cluster-level:**
- Node CPU, memory, disk usage
- Pod scheduling and distribution
- Cluster capacity and utilization
- Network throughput

**Application-level:**
- HTTP request rates (per endpoint, per pod)
- Response times and latency percentiles
- Error rates (4xx, 5xx responses)
- Request/response sizes

**Kubernetes objects:**
- Deployment status and health
- ReplicaSet scaling events
- Pod restarts and OOMKills
- Container resource limits vs actual usage

## Monitoring the Demo App

For my 8-pod demo-app deployment, I can now see:
- Total request rate across all pods
- Individual pod performance
- Memory and CPU usage per pod
- Distribution of requests across pods (load balancing)
- Rolling update progress when deploying new versions

The pre-built dashboards handle all of this without any custom configuration.

## What I Learned

- **Helm simplifies complex deployments** - one command installs everything
- **NodePort makes homelab access easier** - no need for port-forwarding or ingress
- **kube-prometheus-stack is batteries-included** - production-ready monitoring out of the box
- **ServiceMonitor labels are critical** - must match Prometheus selectors
- **Pre-built dashboards are excellent** - cover 90% of monitoring needs
- **Application instrumentation is simple** with the right library
- **7-day retention is plenty** for a homelab (adjust for production)

## Challenges & Solutions

**Challenge: ServiceMonitor not appearing in Prometheus**
- **Problem:** Created ServiceMonitor but it didn't show up in Prometheus targets at all - not even as "DOWN"
- **Root cause:** The Service port didn't have a name, and the ServiceMonitor referenced `port: http`
- **Solution:** Added `name: http` to the Service port definition (port 80, targetPort 8000). The ServiceMonitor's `port: http` field must match this exact name. Once the names matched, Prometheus immediately discovered all 8 pod targets.

## Architecture Overview
```
┌─────────────────┐
│   Demo App      │ ──► /metrics endpoint (port 8000)
│   (8 pods)      │
└─────────────────┘
         │
         │ scrape every 30s
         ▼
┌─────────────────┐
│  Prometheus     │ ──► stores 7 days of metrics
│  (NodePort      │     (accessible at :30090)
│   30090)        │
└─────────────────┘
         │
         │ PromQL queries
         ▼
┌─────────────────┐
│   Grafana       │ ──► visualize dashboards
│  (NodePort      │     (accessible at :30030)
│   30030)        │
└─────────────────┘
```

## Next Possible Steps

The monitoring stack is now complete. Potential future enhancements:
- **Alerting** - Configure Alertmanager for Slack/email notifications on critical events
- **Logging** - Add Loki for centralized log aggregation
- **Tracing** - Implement distributed tracing with Jaeger or Tempo
- **Custom dashboards** - Build application-specific dashboards for business metrics
- **Long-term storage** - Configure remote storage for metrics beyond 7 days