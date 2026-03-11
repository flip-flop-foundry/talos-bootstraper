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
  pxe/                   # iPXE network boot infrastructure (Docker-based)
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
| Talos | `OVERLAY_NAME`, `CLUSTER_EXTERNAL_DOMAIN`, `POD_CIDR`, `SERVICE_CIDR`, `KUBERNETES_VERSION`, `TALOS_CONTROL_NODES`, `TALOS_WORKER_NODES`, `TALOS_INSTALL_VERSION`, `TALOS_INSTALLER_TYPE`, `TALOS_SCHEMATIC_EXTENSIONS`, `TALOS_SCHEMATIC_EXTRA_KERNEL_ARGS` |
| Helm versions | `CILIUM_HELM_VERSION`, `TRAEFIK_HELM_VERSION`, `ARGOCD_HELM_VERSION`, `CERT_MGR_HELM_VERSION`, `LONGHORN_CHART_VERSION`, `CNPG_HELM_VERSION`, `EXTERNAL_DNS_HELM_VERSION`, `METRICS_SERVER_HELM_VERSION`, `RELOADER_HELM_VERSION`, `GITEA_HELM_VERSION` |
| Networking | `CILIUM_LB_IP_CIDR` (LoadBalancer IP pool), `CILIUM_BGP_LOCAL_ASN`, `CILIUM_BGP_PEER_ASN`, `CILIUM_BGP_PEER_ADDRESS` (BGP only) |
| Storage | `LONGHORN_BACKUP_TARGET`, `LONGHORN_BACKUP_CRON_SCHEDULE`, `LONGHORN_BACKUP_RETAIN` |
| DNS | `EXTERNAL_DNS_BINDSERVER_IP`, `EXTERNAL_DNS_TSIG_KEYNAME`, `EXTERNAL_DNS_DOMAIN_FILTERS` |
| Gitea | `GITEA_DOMAIN_NAME`, `GITEA_CLUSTER_SERVICES_REPO_URL`, `GITEA_HELM_VERSION` |
| ArgoCD | `ARGOCD_DOMAIN`, `ARGOCD_HELM_VERSION` |
| PXE Boot | `TALOS_PXE_ENABLED`, `TALOS_PXE_SERVER_IP`, `TALOS_PXE_SERVER_PORT`, `TALOS_PXE_PROXY_DHCP_ENABLED`, `TALOS_PXE_DHCP_RANGE` |
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
| `adminTasks/pxe-setup.sh` | iPXE network boot setup: schematic, assets, firmware, Docker |
| `adminTasks/lib/image-factory.sh` | Talos Image Factory API: schematics, asset downloads, iPXE build |

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

## LoadBalancer Mode (L2 vs BGP)

Cilium provides LoadBalancer IP advertisement via two modes, toggled through `EXCLUDED_BASE`:

### L2 Mode (default)

Uses ARP announcements on the node network. IPs must be from the node subnet and excluded from DHCP.

- `CILIUM_LB_IP_CIDR`: Range on node subnet (e.g. `192.168.1.200/28`)
- `EXCLUDED_BASE` must include the three BGP CRD files:
  ```
  "cilium/ciliumBGPClusterConfig.yaml"
  "cilium/ciliumBGPPeerConfig.yaml"
  "cilium/ciliumBGPAdvertisement.yaml"
  ```

### BGP Mode

Advertises LoadBalancer IPs via eBGP to an external router. IPs can be any routable CIDR.

- `CILIUM_LB_IP_CIDR`: Any routable CIDR not overlapping Pod/Service CIDRs
- `CILIUM_BGP_LOCAL_ASN`: Cluster BGP ASN (e.g. `64513`)
- `CILIUM_BGP_PEER_ASN`: Router BGP ASN (e.g. `64512`)
- `CILIUM_BGP_PEER_ADDRESS`: Router IP address
- `EXCLUDED_BASE` must include the L2 policy file:
  ```
  "cilium/ciliumL2AnnouncementPolicy.yaml"
  ```
- Overlay must add `talos/talosPatchConfig.yaml` with `machine.nodeLabels.bgpPeer: "true"`

### Key Design

- `CiliumLoadBalancerIPPool` is common to both modes
- Services (Traefik, ArgoCD) are mode-agnostic — no `loadBalancerClass` needed since Cilium is the sole LB controller
- Mode selection is purely which Cilium CRDs get rendered, controlled by `EXCLUDED_BASE`

See `overlays/yourCluster-l2/` and `overlays/yourCluster-bgp/` for complete examples.

## iPXE Network Boot

Optional PXE boot infrastructure for automated Talos OS installation on bare metal nodes.

**Setup**: `./adminTasks/pxe-setup.sh overlays/<cluster>/<cluster>.env`

This creates a Talos Image Factory schematic, downloads kernel/initramfs assets, generates boot scripts, and starts Docker containers for serving the boot environment.

### Two Modes

| Mode | When to Use | How It Works |
|------|-------------|-------------|
| **Manual DHCP** (`TALOS_PXE_PROXY_DHCP_ENABLED=false`) | PXE server on different subnet from nodes, or router supports DHCP options | Builds custom iPXE firmware with embedded chainload script. Router DHCP options 66 (next-server) + 67 (boot file) point to TFTP server. TFTP serves `ipxe.efi` → chains to HTTP boot script → loads kernel + initramfs |
| **ProxyDHCP** (`TALOS_PXE_PROXY_DHCP_ENABLED=true`) | PXE server on same subnet as nodes, no router config needed | dnsmasq runs as proxyDHCP alongside existing DHCP. Broadcasts boot info (next-server + boot script URL) without assigning IPs |

### PXE Infrastructure (`adminTasks/pxe/`)

```
pxe/
  docker-compose.yml       # 3 services: pxe-server (nginx), dnsmasq (proxyDHCP), tftp
  Dockerfile.ipxe          # Two-stage cached iPXE UEFI firmware build
  dnsmasq.conf.template    # proxyDHCP config template
  ipxe-boot.ipxe.template  # Boot script template (kernel + initramfs URLs)
  nginx.conf               # Static file server config
  .gitignore               # Excludes assets/, dnsmasq.conf, tftp/, embed.ipxe
```

### Key Implementation Details

- **Image Factory API** returns HTTP 302 redirects to S3-signed URLs — `curl -L` is required
- **TFTP in Docker** requires `--tftp-single-port` flag because Docker UDP NAT only forwards the initial port (69), not ephemeral response ports
- **poseidon/dnsmasq** (`quay.io/poseidon/dnsmasq:v0.5.0`) needs `-k` flag for foreground mode in Docker
- **iPXE build** uses two-stage Docker build: stage 1 caches full compilation, stage 2 only re-links with new embedded script (~10s)

## How to Add a New Cluster

1. Create `overlays/<cluster>/<cluster>.env` (copy from `overlays/yourCluster-l2/` or `overlays/yourCluster-bgp/`)
2. Update: `OVERLAY_NAME`, `CLUSTER_EXTERNAL_DOMAIN`, CIDRs, node hostnames, versions
3. Choose LoadBalancer mode and configure `EXCLUDED_BASE` accordingly (see above)
4. Create `overlays/<cluster>/talos/` with generated machine configs
5. Run `./adminTasks/render-overlay.sh overlays/<cluster>/<cluster>.env`
6. Run `./adminTasks/cluster-bootstrap.sh overlays/<cluster>/<cluster>.env`

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

## Copilot Coding Agent — Working Instructions

These instructions apply whenever the Copilot Coding Agent picks up an issue in this repository.

### Before Writing Any Code

1. **Read the issue carefully.** Identify every explicit requirement and any implicit constraints.
2. **Ask clarifying questions first.** If any requirement is ambiguous — or if fulfilling it would require touching files not mentioned in the issue — post a comment on the issue asking for clarification **before** opening a pull request or writing code. Wait for a response. Do not guess.
3. **Acknowledge scope.** Briefly summarise in an issue comment what you plan to change and why, so the requester can correct misunderstandings early.
4. If possible with out adding a lot of complexity, avoid breaking existing clusters. Breaking existing clusters/deployments can be acceptable, if **stated very clearly** and **explained why** this is needed


### Making Changes

- **Minimal changes only.** Solve exactly what the issue asks. Do not refactor unrelated code, update unrelated versions, or add unrequested features.
- **Follow existing patterns.** Match the style of the file you are editing:
  - Shell scripts: `set -euo pipefail`, use `lib/logging.sh` helpers (`log_info`, `log_success`, `log_warn`, `log_error`), `readonly` for constants.
  - YAML templates: use `${VARIABLE}` placeholders consistent with the existing whitelist; follow the ArgoCD multi-source pattern for new ArgoApps.
  - Env files: `export VAR="value"` format.
- **Keep `CLAUDE.md` and `.github/copilot-instructions.md` in sync.** If you modify either file, apply the identical change to the other.
- **Do not commit secrets.** Never write real credentials, tokens, or private keys into any file.

### Validating Changes

Before raising a pull request, run the following checks inside the agent environment:

```bash
# Lint all shell scripts
shellcheck adminTasks/*.sh adminTasks/lib/*.sh

# Verify the render pipeline is not broken (using an example overlay)
./adminTasks/render-overlay.sh overlays/yourCluster-l2/yourCluster-l2.env
```

### Pull Request Guidelines

- **Title**: short, imperative, describes the change (e.g. `feat: add NTP server config to Talos patch`).
- **Description**: explain *what* changed, *why*, and list every file modified.
- **One concern per PR.** If an issue covers multiple unrelated concerns, raise separate PRs or ask the requester how to proceed.
- **Do not self-merge.** Always request a human review.
