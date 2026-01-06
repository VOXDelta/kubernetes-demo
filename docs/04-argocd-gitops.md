# 04 - GitOps with ArgoCD

## Overview
Implementing GitOps automation with ArgoCD to continuously monitor Git for changes and automatically deploy updates to the Kubernetes cluster.

## Why GitOps?

Initially, I was manually triggering deployments with `kubectl apply` after each pipeline run. This worked for a single app, but it's not scalable:
- Manual intervention required for every deployment
- No automatic rollback capability
- Difficult to track what's actually running vs what's in Git
- Doesn't scale when managing multiple services

**GitOps solves this** by treating Git as the single source of truth. ArgoCD continuously watches the repository and ensures the cluster state matches what's defined in Git.

## ArgoCD Installation

ArgoCD runs as a set of services within the Kubernetes cluster itself.

### Installation Process
```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

# Verify installation
kubectl get pods -n argocd
```

All ArgoCD components should show "Running" status:
```
NAME                                      READY   STATUS    AGE
argocd-application-controller-0           1/1     Running   5m
argocd-applicationset-controller-xxx      1/1     Running   5m
argocd-dex-server-xxx                     1/1     Running   5m
argocd-notifications-controller-xxx       1/1     Running   5m
argocd-redis-xxx                          1/1     Running   5m
argocd-repo-server-xxx                    1/1     Running   5m
argocd-server-xxx                         1/1     Running   5m
```

### Accessing the Web UI

K3s automatically exposed ArgoCD on a NodePort during installation - I could access it at `https://10.0.0.2:30670` without any additional configuration.
```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access the UI at: `https://10.0.0.2:30670`

**Login credentials:**
- Username: `admin`
- Password: (from the command above)

## Repository Connection

Since my repository was private during development (now public), I connected it via SSH for secure access.

### Adding SSH Key to GitHub
```bash
# Generate SSH key (on the k3s-master node)
ssh-keygen -t ed25519 -C "argocd@k3s-cluster"

# Copy the public key
cat ~/.ssh/id_ed25519.pub
```

Add this public key to GitHub: Repository → Settings → Deploy Keys → Add deploy key

**Important:** "Allow write access" is NOT needed - ArgoCD only reads from the repository.

### Connecting Repository in ArgoCD

In the ArgoCD UI:
1. Settings → Repositories → Connect Repo
2. Connection Method: SSH
3. Repository URL: `git@github.com:VOXDelta/kubernetes-demo.git`
4. SSH Private Key: (paste the private key from `~/.ssh/id_ed25519`)
5. Click "Connect"

Status should show "Successful" with a green checkmark.

## Application Setup

Now comes the actual application configuration - telling ArgoCD what to deploy and where.

### Creating the Application

In ArgoCD UI:
1. Applications → New App
2. Fill in the configuration:

**General:**
- Application Name: `demo-app`
- Project: `default`
- Sync Policy: `Automatic` (more on this below)

**Source:**
- Repository URL: `git@github.com:VOXDelta/kubernetes-demo.git`
- Revision: `HEAD` (tracks the main branch)
- Path: `k8s` (where the manifests are stored)

**Destination:**
- Cluster URL: `https://kubernetes.default.svc` (in-cluster)
- Namespace: `demo-ha`

**Sync Options:**
- ✅ Auto-Create Namespace
- ✅ Prune Resources (delete resources removed from Git)
- ✅ Self Heal (revert manual kubectl changes)

Click "Create" and ArgoCD immediately starts syncing.

## Auto-Sync Configuration

The magic of GitOps happens with auto-sync enabled. Here's how it works:

**Without auto-sync:**
- ArgoCD detects changes but waits
- Manual sync required via UI or CLI
- Useful for staging environments

**With auto-sync (what I'm using):**
- ArgoCD polls Git every ~3 minutes
- Detects manifest changes automatically
- Applies changes to the cluster
- No manual intervention needed

**Self-heal feature:**
If someone manually modifies resources with `kubectl` (e.g., changes replicas), ArgoCD reverts the change back to what's in Git within minutes. Git is the source of truth.

## The Complete GitOps Flow

Here's what happens when I push code:

1. **Code push** → Triggers GitHub Actions
2. **Pipeline builds** image with SHA tag
3. **Pipeline pushes** to private registry
4. **Pipeline updates** `k8s/deployment.yaml` with new SHA
5. **Pipeline commits** changes to Git
6. **ArgoCD detects** change (within ~3 minutes)
7. **ArgoCD syncs** - pulls new image and updates pods
8. **Kubernetes performs** rolling update
9. **New version running**

Total time from code push to deployment: **~5 minutes**, fully automated.

## Production-Grade Configuration

My demo app is currently configured with:
- **8 replicas** - ensures high availability across nodes
- **2 revision history** - allows rollback to previous version
```yaml
spec:
  replicas: 8
  revisionHistoryLimit: 2
```

**Is this overkill for a demo?** Absolutely. But it demonstrates production patterns:
- **High availability** - app stays up even if nodes fail
- **Rolling updates** - zero-downtime deployments
- **Quick rollbacks** - revert to previous version if needed

In production with real traffic, you'd tune these numbers based on:
- Expected load
- Resource constraints
- Deployment frequency

## Verifying the Deployment

Check that everything is running:
```bash
# Check application status in ArgoCD
kubectl get applications -n argocd

# Expected output:
# NAME       SYNC STATUS   HEALTH STATUS
# demo-app   Synced        Healthy

# Check the actual pods
kubectl get pods -n demo-ha

# Should see 8 pods running:
# NAME                        READY   STATUS    RESTARTS   AGE
# demo-app-747d96884c-xxxxx   1/1     Running   1          7d
# demo-app-747d96884c-xxxxx   1/1     Running   1          7d
# ... (8 total)
```

## What I Learned

- **GitOps eliminates manual deployment steps** - once configured, everything is automatic
- **Git becomes the control plane** - all changes flow through version control
- **Self-heal prevents configuration drift** - cluster state always matches Git
- **ArgoCD's UI provides great visibility** - easy to see sync status and health
- **SSH deploy keys are simpler than personal tokens** for repository access
- **Auto-sync interval (~3 minutes) is a good balance** between responsiveness and API load
- **K3s NodePort auto-exposure** made ArgoCD UI access straightforward

## Challenges & Solutions

**Challenge 1: Initial sync failed**
- **Problem:** Namespace didn't exist
- **Solution:** Enabled "Auto-Create Namespace" in sync options

**Challenge 2: Manual kubectl changes kept getting reverted**
- **Problem:** Confused why changes disappeared
- **Solution:** Realized this is self-heal working as intended - make changes in Git!

**Challenge 3: ArgoCD not detecting changes**
- **Problem:** Manifest updates not triggering sync
- **Solution:** ArgoCD polls every ~3 minutes - patience required

## Next Possible Steps

With GitOps operational, several enhancements are possible:
- **Monitoring Stack** - Add observability to track deployments
- **Secrets Management** - Vault for secure credential handling  
- **Multi-Environment Setup** - Separate dev/staging/prod clusters