# 02 - Docker Registry & Self-Hosted CI/CD Runner

## Overview
Setting up a private Docker registry for storing container images locally and configuring a GitHub Actions self-hosted runner for the CI/CD pipeline.

## Why a Private Registry?

Instead of using Docker Hub or GitHub Container Registry, I wanted a local solution:
- **Faster builds** - no internet upload/download for every image
- **Privacy** - all images stay in my network
- **Learning** - understanding registry internals and authentication
- **Cost** - no rate limits or storage fees

## Registry Setup

I run multiple Docker containers on a dedicated LXC container (192.168.1.171) in my homelab. Since I use docker-compose for all my services, adding the registry was straightforward.

### Docker Compose Configuration
```yaml
services:
  registry:
    image: registry:2
    container_name: registry
    restart: always
    ports:
      - "5000:5000"
    environment:
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
    volumes:
      - ./volumes/registry-data:/var/lib/registry
      - ./auth:/auth:ro
```

### Authentication Setup

The registry requires basic authentication. I created the htpasswd file:
```bash
mkdir auth
docker run --rm --entrypoint htpasswd \
  httpd:2 -Bbn myuser mypassword > auth/htpasswd
```

**Security note:** The credentials are stored locally on the Docker host. For production environments, these could be managed through a credential keeper or secrets management solution. For the CI/CD pipeline, the registry credentials are stored as **GitHub Actions Secrets** (`REGISTRY_USER` and `REGISTRY_PASSWORD`), which keeps them encrypted and separate from the codebase.

### Starting the Registry
```bash
docker-compose up -d

# Verify it's running
docker ps | grep registry
curl http://192.168.1.171:5000/v2/_catalog
```

## Configuring Kubernetes Nodes for Insecure Registry

Since my registry uses HTTP (not HTTPS), I needed to configure all K3s nodes to allow insecure registry access:
```bash
# On each K3s node (master and workers)
mkdir -p /etc/rancher/k3s

cat <<EOF > /etc/rancher/k3s/registries.yaml
mirrors:
  "192.168.1.171:5000":
    endpoint:
      - "http://192.168.1.171:5000"
EOF

# Restart K3s to apply changes
systemctl restart k3s
```

**Note:** In production environments, you'd restart just the K3s service. In my homelab, I sometimes found it faster to simply restart the entire VM to ensure a clean state.

## GitHub Actions Runner: External vs Self-Hosted

### Initial Approach: External Runner

I initially tried using an external GitHub-hosted runner with SSH access to push images to my private registry. The idea was:
1. GitHub runner builds the image
2. SSH into my network
3. Push to local registry

**The problem:** This required exposing my LXC container externally through my firewall and nginx reverse proxy - way too much security risk for a homelab project.

### Solution: Self-Hosted Runner

Instead, I set up a **self-hosted GitHub Actions runner** directly on the same LXC container (192.168.1.171) that hosts the Docker registry.

**How it works:**
- The runner makes **outbound connections** to GitHub (polls for jobs)
- No inbound firewall rules needed
- Runner has direct local access to the registry
- Everything stays internal to my network

### Runner Installation

Following GitHub's instructions for adding a self-hosted runner:
```bash
# On the Docker/Registry LXC (192.168.1.171)
mkdir actions-runner && cd actions-runner

# Download the runner (version varies - check GitHub repo settings)
curl -o actions-runner-linux-x64-2.330.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.330.0/actions-runner-linux-x64-2.330.0.tar.gz

tar xzf ./actions-runner-linux-x64-2.330.0.tar.gz

# Configure with token from GitHub repo settings
./config.sh --url https://github.com/YOUR_USER/YOUR_REPO \
  --token YOUR_TOKEN

# Run the runner
./run.sh
```

The runner now appears in the GitHub repository settings under "Actions → Runners" as online and ready.

## Testing the Setup

Quick test to verify the registry works with authentication:
```bash
# Login to registry
docker login 192.168.1.171:5000 -u myuser -p mypassword

# Tag and push a test image
docker tag demo-app:latest 192.168.1.171:5000/demo-ha/demo-app:test
docker push 192.168.1.171:5000/demo-ha/demo-app:test

# Verify it's in the registry
curl -u myuser:mypassword http://192.168.1.171:5000/v2/_catalog
```

## What I Learned

- **Self-hosted runners eliminate firewall headaches** - they connect outbound to GitHub, not the other way around
- **Running the runner on the same host as the registry** keeps everything local and fast
- **Insecure registries are fine for homelab** but require explicit configuration on all nodes
- **Docker authentication** works the same whether registry is local or remote
- **GitHub Actions Secrets** provide a secure way to handle credentials in CI/CD pipelines without hardcoding them

## Next Steps

With the registry and runner in place, the next phase is building the actual CI/CD pipeline with GitHub Actions to automate image builds and deployments.