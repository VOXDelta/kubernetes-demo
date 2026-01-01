# 03 - GitHub Actions CI/CD Pipeline

## Overview
Building an automated CI/CD pipeline that builds Docker images on every push, stores them in the private registry, and updates Kubernetes manifests for GitOps deployment.

## Pipeline Architecture

The pipeline runs entirely on the self-hosted runner with two main jobs:
1. **Build and Push** - Build Docker image and push to private registry
2. **Update Manifests** - Update deployment.yaml with new image tag

All steps execute locally on the runner (192.168.1.171) - no data leaves my network.

## Initial Pipeline Development

I started with a simple workflow and iteratively added functionality. The journey involved quite a few errors and refinements:
- Getting the SHA extraction working correctly
- Ensuring the registry login works reliably
- Making manifest updates atomic
- Preventing infinite pipeline loops

Let's break down the final working pipeline.

## Pipeline Workflow

### Job 1: Build and Push Image

**Image Tagging Strategy:**

I use the short Git commit SHA (first 7 characters) as the image tag. This provides:
- **Traceability** - every image maps to a specific commit
- **Uniqueness** - no tag collisions
- **Rollback capability** - easy to deploy previous versions
```yaml
- name: Set variables
  id: vars
  run: |
    SHORT_SHA=$(echo ${GITHUB_SHA} | cut -c1-7)
    echo "sha_short=${SHORT_SHA}" >> $GITHUB_OUTPUT
    echo "🏷️  Building image with tag: sha-${SHORT_SHA}"
```

**Registry Login:**

The pipeline authenticates to the private registry using secrets stored in GitHub Actions:
```yaml
- name: Login to Registry
  run: |
    docker login ${{ env.REGISTRY }} \
      -u "${{ secrets.REGISTRY_USER }}" \
      -p "${{ secrets.REGISTRY_PASSWORD }}"
```

These secrets (`REGISTRY_USER` and `REGISTRY_PASSWORD`) are configured in the GitHub repository settings under "Settings → Secrets and variables → Actions".

**Building and Pushing:**
```yaml
- name: Build Docker Image
  run: |
    docker build \
      -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ steps.vars.outputs.sha_short }} \
      -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest \
      .

- name: Push Docker Image
  run: |
    docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ steps.vars.outputs.sha_short }}
    docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
```

Each build creates two tags:
- `sha-XXXXXXX` - specific version for this commit
- `latest` - always points to most recent build

### Job 2: Update Kubernetes Manifests

This is where GitOps comes in. The pipeline automatically updates the deployment manifest with the new image tag.

**Why this is necessary:**

ArgoCD (covered in detail in `04-argocd-gitops.md`) continuously watches the Git repository for changes. When the deployment.yaml changes, ArgoCD automatically deploys the new version to Kubernetes. By updating the manifest in Git, we trigger the deployment without any manual kubectl commands.

**Manifest Update Process:**
```yaml
- name: Update deployment.yaml
  run: |
    SHORT_SHA="${{ needs.build-and-push.outputs.sha-short }}"
    echo "📝 Updating deployment.yaml with image tag: sha-${SHORT_SHA}"
    
    sed -i "s|image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-.*|image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${SHORT_SHA}|g" k8s/deployment.yaml
    
    echo "✅ Updated deployment.yaml"
    echo "Changes:"
    git diff k8s/deployment.yaml
```

The `sed` command finds the image line and replaces the old SHA with the new one.

**Committing and Pushing:**
```yaml
- name: Commit and Push
  run: |
    SHORT_SHA="${{ needs.build-and-push.outputs.sha-short }}"
    
    git config user.name "GitOps Bot"
    git config user.email "gitops@bot.local"
    
    git add k8s/deployment.yaml
    
    if git diff --staged --quiet; then
      echo "ℹ️  No changes to commit"
    else
      git commit -m "🚀 Update image to sha-${SHORT_SHA} [skip ci]"
      git push
      
      echo "✅ Manifest updated in Git"
      echo "⏳ ArgoCD will auto-sync within ~3 minutes"
    fi
```

**Critical detail:** The `[skip ci]` tag in the commit message prevents an infinite loop. Without it:
1. Pipeline updates deployment.yaml
2. Commits to Git
3. Triggers another pipeline run
4. Which updates deployment.yaml again
5. Loop forever

With `[skip ci]`, GitHub Actions ignores commits with this tag.

## Preventing Infinite Loops

Another safeguard is in the workflow trigger configuration:
```yaml
on:
  push:
    branches:
      - main
    paths-ignore:
      - 'k8s/deployment.yaml'
```

This ensures the pipeline only runs when application code changes, not when deployment.yaml is updated.

## Complete Pipeline Flow

Here's what happens when I push code:

1. **Trigger:** Push to main branch (excluding deployment.yaml changes)
2. **Build Job:**
   - Checkout code
   - Extract short SHA
   - Login to registry
   - Build image with SHA tag
   - Push to private registry
3. **Update Job:**
   - Checkout code (again, to get fresh copy)
   - Update deployment.yaml with new SHA
   - Commit changes with `[skip ci]`
   - Push to Git
4. **ArgoCD:** Detects manifest change and deploys new version (see next doc)

Total time: ~2-3 minutes from code push to pods running new version.

## Challenges & Solutions

**Challenge 1: Registry authentication failures**
- **Problem:** Inconsistent login issues
- **Solution:** Moved credentials to GitHub Secrets, ensured runner has Docker login cached

**Challenge 2: Manifest updates not triggering**
- **Problem:** Sometimes sed wouldn't match the image line
- **Solution:** Made the regex more specific with `sha-.*` pattern

**Challenge 3: Infinite pipeline loops**
- **Problem:** Pipeline triggering itself endlessly
- **Solution:** Added `[skip ci]` tag and `paths-ignore` for deployment.yaml

**Challenge 4: Job dependencies**
- **Problem:** Update job tried to run before build completed
- **Solution:** Used `needs: build-and-push` and job outputs to pass SHA between jobs

## Testing the Pipeline

To verify everything works:
```bash
# Make a small change to trigger the pipeline
echo "test X" >> README.md

# Commit and push
git add README.md
git commit -m "test X"
git push

# Watch the pipeline in GitHub Actions
# Check the logs for each step
```

Within minutes, the new image should be in the registry and the deployment.yaml should be updated with the new SHA.

## What I Learned

- **GitHub Actions Secrets** are essential for keeping credentials secure
- **Job outputs** allow passing data between jobs in a workflow
- **Infinite loops are easy to create** in CI/CD - always think about feedback cycles
- **GitOps pattern** (Git as source of truth) simplifies deployments significantly
- **Self-hosted runners** make local registry integration seamless

## Next Steps

With the CI/CD pipeline automatically building and updating manifests, the next piece is ArgoCD - the GitOps controller that watches Git and deploys changes to Kubernetes.