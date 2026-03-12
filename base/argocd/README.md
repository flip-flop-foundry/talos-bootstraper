# ArgoCD

## What it does

[ArgoCD](https://argo-cd.readthedocs.io/) is the GitOps continuous delivery controller for this cluster. It continuously reconciles the cluster state against the desired state declared in the Gitea repository, automatically syncing, self-healing, and pruning resources.

ArgoCD is both the **tool that deploys everything** and a **workload that is itself deployed and managed** (after the initial bootstrap).

## Why it was added

ArgoCD is the core GitOps engine of this cluster. Every other component is deployed and managed as an ArgoCD `Application`, giving a single pane of glass for cluster state and enabling declarative, auditable change management.

## Dependencies

- **gitea** — After bootstrap, ArgoCD's production configuration points at the Gitea repository. Gitea must be healthy for ArgoCD to reconcile cluster state.
- **cert-manager** — The ArgoCD repo-server uses a cert-manager-issued certificate (`argocdRepoServerCertificate.yaml`) for secure communication.

## Dependents

Every other component in this repository is a dependent of ArgoCD — they are all managed as ArgoCD `Application` resources.

## User Guide

### Accessing the ArgoCD UI

The ArgoCD UI is exposed via a Traefik `IngressRoute` at `https://${ARGOCD_DOMAIN}`. DNS is managed by external-dns automatically.

### Admin credentials

The initial admin password is auto-generated and stored in a Kubernetes `Secret`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

It is recommended to change this password after first login.

### Checking application sync status

```bash
# List all applications
kubectl -n argocd get applications

# Describe a specific application
kubectl -n argocd describe application <app-name>
```

### Forcing a sync

```bash
kubectl -n argocd app sync <app-name>
```

### Bootstrap vs production configuration

During cluster bootstrap, ArgoCD is installed with a temporary bootstrap values file (`argocdHelmBootstrapValues.yaml`) that points at the local git-bootstrap-server pod. After Gitea is ready, `cluster-bootstrap.sh` upgrades ArgoCD to the production values file (`argocdHelmValues.yaml`) that points at Gitea.
