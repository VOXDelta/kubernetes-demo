# 01 - Infrastructure Setup & Kubernetes Installation

## Overview
Setting up a 3-node Kubernetes cluster on my Proxmox homelab to learn Kubernetes fundamentals and build a foundation for GitOps workflows.

**Environment:**
- Proxmox VE homelab
- 3-node K3s cluster (1 control plane, 2 workers)
- Debian 13 base OS

## LXC vs VM: Learning the Hard Way

I started with LXC containers because they're more resource-efficient than VMs - less overhead, faster startup. Made sense for a homelab, right?

**The problem:** K3s needs deep kernel access for container networking and the shared kernel between LXC and Proxmox became a blocker. I ran into issues with:
- Kernel module conflicts during K3s installation
- CNI plugin compatibility issues
- Limited isolation for the networking stack

Rather than reconfiguring my entire Proxmox host to accommodate LXC, I switched to full VMs. More overhead, but proper isolation and no shared kernel headaches.

## Building the VM Template

I chose **Debian 13** as the base - lightweight, stable, and minimal configuration needed.

### Base Configuration

After a clean Debian install, I configured the essentials for Kubernetes:
```bash
# Install required tools
apt install -y \
    curl \
    wget \
    vim \
    htop \
    net-tools \
    iputils-ping \
    ca-certificates \
    gnupg

# Disable swap (Kubernetes requirement)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel module for container networking
modprobe br_netfilter
echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf

# Kernel parameters for Kubernetes
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
```

Then I converted this configured VM into a Proxmox template - this lets me clone identical nodes quickly and ensures consistency across the cluster.

## Cluster Architecture

| Node | Hostname | IP | RAM | CPU | Disk |
|------|----------|-----|-----|-----|------|
| Control Plane | k3s-master | 10.0.0.2 | 8GB | 4 | 20GB |
| Worker 1 | k3s-node-1 | 10.0.0.3 | 4GB | 2 | 20GB |
| Worker 2 | k3s-node-2 | 10.0.0.4 | 4GB | 2 | 20GB |

### Post-Clone Configuration

After cloning from the template, each node needs unique identifiers:
```bash
# Set unique hostname
hostnamectl set-hostname k3s-master  # or k3s-node-1, k3s-node-2

# Configure static IP (edit for each node)
nano /etc/network/interfaces

# Restart networking
systemctl restart networking

# Regenerate SSH host keys
dpkg-reconfigure openssh-server

# Regenerate machine ID
systemd-machine-id-setup
```

## K3s Installation

### Control Plane Setup

On the master node (10.0.0.2):
```bash
curl -sfL https://get.k3s.io | sh -
```

K3s installs as a systemd service. Give it about 30 seconds to start up, then verify:
```bash
# Check the service status
systemctl status k3s

# Should show:
# ● k3s.service - Lightweight Kubernetes
#    Active: active (running)

# Verify the node is ready
kubectl get nodes

# Expected output:
# NAME         STATUS   ROLES                  AGE   VERSION
# k3s-master   Ready    control-plane,master   45s   v1.33.6+k3s1
```

**Important:** Wait for STATUS to show "Ready" before proceeding. If it shows "NotReady", give it another 30 seconds.

### Getting the Join Token

Worker nodes need a token to join the cluster. Retrieve it from the master:
```bash
cat /var/lib/rancher/k3s/server/node-token
```

This outputs a long token string - copy it, you'll need it for the next step.

### Adding Worker Nodes

On each worker node (10.0.0.3 and 10.0.0.4), run:
```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://10.0.0.2:6443 \
  K3S_TOKEN="<token>" \
  sh -
```

**Note:** Replace `<token>` with the actual token from the master node. Keep this token secure - it's essentially the password to your cluster.

### Cluster Verification

Back on the master node:
```bash
kubectl get nodes

# Expected output:
# NAME         STATUS   ROLES                  AGE   VERSION
# k3s-master   Ready    control-plane,master   5m    v1.33.6+k3s1
# k3s-node-1   Ready    <none>                 2m    v1.33.6+k3s1
# k3s-node-2   Ready    <none>                 2m    v1.33.6+k3s1
```

All three nodes showing "Ready" - cluster is operational!

## Troubleshooting Tips

If you run into issues, these commands are helpful:
```bash
# Check K3s service logs
journalctl -u k3s -f

# Check which ports K3s is listening on (should see 6443)
ss -tlnp

# Restart K3s service if needed
systemctl restart k3s
```

## What I Learned

- **LXC looks good on paper** but the shared kernel is a dealbreaker for Kubernetes workloads
- **VM templates are essential** - being able to quickly spin up consistent nodes saved hours during setup and later troubleshooting
- **K3s is remarkably simple** - one command gets you a working cluster, no complicated configuration needed
- **The 30-second rule** - K3s needs time to initialize, don't panic if nodes aren't immediately "Ready"



## Initial Testing

Before setting up the full infrastructure, I wanted to verify the cluster could actually run workloads. I built a simple FastAPI demo app with a Dockerfile, transferred the image to one of the nodes via SCP, and deployed it to the cluster.

The pods came up fine, distributed across both worker nodes - cluster networking and scheduling worked as expected. This same demo app became the foundation for all further testing with the registry and CI/CD pipeline.

With the cluster validated, the next step was setting up a private Docker registry for local image storage.


