# Talos Kubernetes Bootstrapper — AI Context Instructions

> **SYNC NOTICE**: This file is mirrored in `CLAUDE.md` (for Claude Code) and `.github/copilot-instructions.md` (for GitHub Copilot).
> If you modify either file, you **must** apply the same changes to the other file to keep them in sync.

## Project Overview

GitOps-based Talos Kubernetes cluster bootstrapper. Automates provisioning of production-grade K8s clusters from bare metal to fully operational, using a three-tier templating system and ArgoCD for ongoing management.

**Owner**: flip-flop-foundry | **Repo**: talos-bootstraper

## Directory Structure

```
base/                    # Component templates with ${VAR} placeholders (cluster-agnostic)
overlays/                # Cluster-specific .env files + optional YAML overrides
  <cluster>/
    <cluster>.env        # All cluster config: versions, CIDRs, domains, node lists
    talos/               # Generated Talos machine configs + secrets
rendered/                # OUTPUT (gitignored) — final manifests after envsubst + yq merge
adminTasks/              # Bootstrap and rendering scripts
  lib/                   # Shared shell libraries (logging, k8s helpers, API clients)
```

### Base Components (base/)

Each subdirectory is a self-contained component:
argocd, cert-manager, cilium, cluster-wide, cnpg, csi-snapshot-controller, external-dns,
gitea, gitea-runners, longhorn, metrics-server, reloader, talos, traefik

## Templating System

- **Engine**: `envsubst` (GNU gettext) for `${VARIABLE}` substitution
- **Merging**: `yq` deep-merge — overlay files override base files of the same name (overlay wins)
- **Safety**: A variable whitelist prevents accidental substitution of placeholders not defined in the .env
- **Exclusions**: The `EXCLUDED_BASE` array in .env can skip entire components or individual files

### Rendering Pipeline

```
base/<component>/*.yaml  ──┐
                            ├──> yq merge (overlay wins) ──> envsubst ──> rendered/<cluster>/<component>/
overlays/<cluster>/<component>/*.yaml ─┘
```

Run: `./adminTasks/render-overlay.sh overlays/<cluster>/<cluster>.env`

## File Naming Conventions

- ArgoCD Application: `<component>ArgoApp.yaml`
- Helm values: `<component>HelmValues.yaml`
- Bootstrap secrets: `<component>SecretsBootstrap.yaml`
- Certificates/issuers: `<component>Certificate.yaml`, `<component>Issuer.yaml`
- Overlay env file: `overlays/<cluster>/<cluster>.env`

## ArgoCD Patterns

### Multi-Source Applications

Every ArgoCD app uses two sources:
1. **Helm chart source** — external chart repo, pinned version via `${COMPONENT_HELM_VERSION}`
2. **Git values source** — this repo (Gitea), with `ref: values` so helm can reference `$values/rendered/...`

```yaml
sources:
  - chart: <name>
    repoURL: <helm-repo-url>
    targetRevision: ${COMPONENT_HELM_VERSION}
    helm:
      valueFiles:
        - $values/rendered/${OVERLAY_NAME}/<component>/<component>HelmValues.yaml
  - repoURL: ${GITEA_CLUSTER_SERVICES_REPO_URL}
    targetRevision: ${GITEA_CLUSTER_SERVICES_REPO_BRANCH}
    path: rendered/${OVERLAY_NAME}/<component>
    ref: values
```

### Sync Waves (Deployment Order)

- `-50`: Cilium (networking — must be first)
- `-10`: AppProject definitions
- `0`: Most components (default)
- `5`: Gitea (depends on CNPG database)

### Projects

- **cluster-services** (privileged): Can deploy cluster-wide resources (CRDs, namespaces, PriorityClasses)
- **default** (restricted): Blocked from system namespaces and cluster-scoped resources

### Special Labels

- `initial-deploy-with-kubectl: "true"` — deployed via kubectl before ArgoCD takes over

## Bootstrap Workflow

```
1. cluster-initialSetup.sh  → Install prerequisites, generate Talos machine configs
2. [Manual]                  → Install Talos OS on nodes
3. cluster-bootstrap.sh      → Full bootstrap ceremony:
   ├─ Setup kubeconfig + helm repos
   ├─ Install Cilium (helm template | kubectl apply)
   ├─ Install ArgoCD with bootstrap values
   ├─ Deploy git-bootstrap-server pod (temporary Alpine Git)
   ├─ kubectl apply manifests with initial-deploy-with-kubectl label
   ├─ Deploy all ArgoCD Applications
   ├─ gitea-bootstrap.sh → Create Gitea org/repo, push code, create ArgoCD credentials
   ├─ Re-render with production Gitea URL
   └─ Upgrade ArgoCD to final config pointing at Gitea
4. ArgoCD manages everything → auto-sync, self-heal, prune
```

## Overlay .env File Structure

Each cluster has one `.env` file exporting all configuration. Key variable groups:

| Group | Example Variables |
|-------|-------------------|
| Talos | `OVERLAY_NAME`, `CLUSTER_EXTERNAL_DOMAIN`, `POD_CIDR`, `SERVICE_CIDR`, `KUBERNETES_VERSION`, `TALOS_CONTROL_NODES`, `TALOS_WORKER_NODES` |
| Helm versions | `CILIUM_HELM_VERSION`, `TRAEFIK_HELM_VERSION`, `ARGOCD_HELM_VERSION`, `CERT_MGR_HELM_VERSION`, `LONGHORN_CHART_VERSION`, `CNPG_HELM_VERSION`, `EXTERNAL_DNS_HELM_VERSION`, `METRICS_SERVER_HELM_VERSION`, `RELOADER_HELM_VERSION`, `GITEA_HELM_VERSION` |
| Networking | `CILIUM_LB_IP_CIDR` (BGP LoadBalancer range) |
| Storage | `LONGHORN_BACKUP_TARGET`, `LONGHORN_BACKUP_CRON_SCHEDULE`, `LONGHORN_BACKUP_RETAIN` |
| DNS | `EXTERNAL_DNS_BINDSERVER_IP`, `EXTERNAL_DNS_TSIG_KEYNAME`, `EXTERNAL_DNS_DOMAIN_FILTERS` |
| Gitea | `GITEA_DOMAIN_NAME`, `GITEA_CLUSTER_SERVICES_REPO_URL`, `GITEA_HELM_VERSION` |
| ArgoCD | `ARGOCD_DOMAIN`, `ARGOCD_HELM_VERSION` |
| Exclusions | `EXCLUDED_BASE` array — skip components or files from rendering |

## Key Scripts Reference

| Script | Purpose |
|--------|---------|
| `adminTasks/render-overlay.sh` | Template renderer: envsubst + yq merge → rendered/ |
| `adminTasks/cluster-bootstrap.sh` | Full bootstrap orchestrator |
| `adminTasks/cluster-initialSetup.sh` | Install prerequisites, generate Talos configs |
| `adminTasks/gitea-bootstrap.sh` | Create Gitea org/repo, push code, setup ArgoCD creds |
| `adminTasks/lib/logging.sh` | Colored output (INFO, SUCCESS, WARN, ERROR) |
| `adminTasks/lib/kubernetes.sh` | kubectl/secret/credential utilities |
| `adminTasks/lib/gitea-api.sh` | Gitea REST API operations |
| `adminTasks/lib/argocd-api.sh` | ArgoCD pod access and login |
| `adminTasks/lib/disk-detection.sh` | Longhorn disk auto-discovery |

## Helm Charts & Repos

| Component | Chart Repo | Version Env Var |
|-----------|-----------|-----------------|
| Cilium | `https://helm.cilium.io/` | `CILIUM_HELM_VERSION` |
| Traefik | `https://traefik.github.io/charts` | `TRAEFIK_HELM_VERSION` |
| cert-manager | `https://charts.jetstack.io` | `CERT_MGR_HELM_VERSION` |
| ArgoCD | `https://argoproj.github.io/argo-helm` | `ARGOCD_HELM_VERSION` |
| Gitea | `https://dl.gitea.com/charts/` | `GITEA_HELM_VERSION` |
| Longhorn | `https://charts.longhorn.io/` | `LONGHORN_CHART_VERSION` |
| CNPG | CloudNativePG | `CNPG_HELM_VERSION` |
| External-DNS | `https://kubernetes-sigs.github.io/external-dns/` | `EXTERNAL_DNS_HELM_VERSION` |
| Metrics Server | `https://kubernetes-sigs.github.io/metrics-server/` | `METRICS_SERVER_HELM_VERSION` |
| Reloader | `https://stakater.github.io/stakater-helm-charts/` | `RELOADER_HELM_VERSION` |

## How to Add a New Cluster

1. Create `overlays/<cluster>/<cluster>.env` (copy from `overlays/yourCluster/yourCluster.env`)
2. Update: `OVERLAY_NAME`, `CLUSTER_EXTERNAL_DOMAIN`, CIDRs, node hostnames, versions
3. Create `overlays/<cluster>/talos/` with generated machine configs
4. Run `./adminTasks/render-overlay.sh overlays/<cluster>/<cluster>.env`
5. Run `./adminTasks/cluster-bootstrap.sh overlays/<cluster>/<cluster>.env`

## How to Add a New Component

1. Create `base/<component>/` directory
2. Add `<component>ArgoApp.yaml` (follow multi-source pattern above)
3. Add `<component>HelmValues.yaml` with `${VAR}` placeholders
4. Add `export COMPONENT_HELM_VERSION="x.y.z"` to each overlay's .env file
5. Optional: Add overlay-specific overrides in `overlays/<cluster>/<component>/`
6. Re-render: `./adminTasks/render-overlay.sh overlays/<cluster>/<cluster>.env`

## Important Notes

- `rendered/` is gitignored — always regenerate via render-overlay.sh
- The bootstrap uses a temporary git-bootstrap-server pod before Gitea is ready
- Shell scripts use `set -euo pipefail` — strict error handling
- All env vars use `export` for shell sourcing and envsubst compatibility
- render-overlay.sh is zsh, cluster-bootstrap.sh is bash
