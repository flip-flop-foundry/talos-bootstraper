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

## Workload Deployment Standards

These standards apply whenever adding new workloads or components to the cluster.

### ArgoCD — Everything as Applications

**Every workload must be deployed as an ArgoCD `Application`**, never as raw `kubectl apply` manifests (except for objects that explicitly need `initial-deploy-with-kubectl: "true"` during bootstrap).

#### Choosing the Right ArgoCD Project

| Project | When to Use | Capabilities |
|---------|-------------|--------------|
| `cluster-services` | Cluster-wide infrastructure (networking, storage, monitoring, ingress, databases, CI/CD) | Can deploy CRDs, Namespaces, ClusterRoles, PriorityClasses, and resources in any namespace |
| `default` | Normal application workloads that are not cluster infrastructure | Restricted from system namespaces; cannot deploy cluster-scoped resources |

Use `cluster-services` for: Cilium, cert-manager, Traefik, Longhorn, CNPG, ArgoCD itself, Gitea, external-dns, monitoring stacks, etc.

Use `default` for: user-facing applications, services that don't need cluster-wide access.

#### Keeping `argocdProjects.yaml` Up To Date

Whenever a new component introduces a **new namespace**, update `base/argocd/argocdProjects.yaml`:

1. Add the namespace to `cluster-services.spec.sourceNamespaces` (allows ArgoCD apps in that namespace to be sources for other apps).
2. Add a `- namespace: "!<new-namespace>"` entry to `default.spec.destinations` (blocks the `default` project from deploying into cluster infrastructure namespaces).
3. Use `${VAR}` placeholders if the namespace is configurable.

Example — adding a new `monitoring` namespace:
```yaml
# In cluster-services.spec.sourceNamespaces:
- "monitoring"

# In default.spec.destinations:
- namespace: "!monitoring"
  server: '*'
```

### Helm over Raw Manifests

**Prefer Helm charts over raw Kubernetes YAML** for all deployments:
- Use the existing [multi-source ArgoCD pattern](#multi-source-applications): one Helm chart source + one Git values source.
- If no Helm chart exists for a workload, use Kustomize or plain YAML as a last resort, but document why.
- Pin chart versions via env var: `export COMPONENT_HELM_VERSION="x.y.z"` in every overlay `.env` file.
- Store Helm value overrides in `base/<component>/<component>HelmValues.yaml` using `${VAR}` placeholders.

### Security Best Practices

Apply the following to every new workload. Where a Helm chart does not support a setting, note it in a comment.

#### Pod and Container Security

```yaml
# Always set on Deployments/StatefulSets/DaemonSets
spec:
  template:
    spec:
      hostUsers: false          # Use user namespace isolation (Kubernetes 1.25+)
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534        # Use a high non-root UID (e.g. nobody)
        runAsGroup: 65534
        fsGroup: 65534
        seccompProfile:
          type: RuntimeDefault  # Enable seccomp filtering
      automountServiceAccountToken: false  # Disable unless the workload needs it
      containers:
        - name: app
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true  # Mount a tmpfs for writable dirs if needed
            capabilities:
              drop:
                - ALL            # Drop all Linux capabilities
              add: []            # Only add back what is strictly required
```

> **Note**: `hostUsers: false` requires Kubernetes 1.25+ with the `UserNamespacesSupport` feature gate enabled (on by default from 1.30). Talos supports this. Check whether the upstream Helm chart has a values key for this — if not, use a post-renderer patch or document the gap.

#### Least-Privilege Service Accounts

- Create a dedicated `ServiceAccount` per workload. Do not share service accounts across components.
- Set `automountServiceAccountToken: false` on the `ServiceAccount` and on pods unless the workload explicitly needs Kubernetes API access.
- Scope `ClusterRole` / `Role` bindings to the minimum required verbs and resources.

#### Network Policies

Add a `NetworkPolicy` for every new namespace that:
1. Defaults to **deny all ingress and egress**.
2. Explicitly allows only the traffic the workload needs (e.g. ingress from Traefik, egress to DNS, egress to the database).

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: <component>-default-deny
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: <component>-allow-dns
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

#### Image Security

- Use specific image tags (never `latest`). Pinning to a digest (`@sha256:...`) is ideal for production.
- Prefer minimal/distroless base images where the upstream chart supports it.
- Enable image pull policy `IfNotPresent` (default) for pinned tags.

### mTLS

**Enable mTLS wherever the application stack supports it.** Cilium provides transparent mTLS via WireGuard node-to-node encryption, but application-level mTLS offers stronger identity guarantees.

- For CNPG databases: always configure mTLS (see [CNPG Database Cluster Pattern](#cnpg-database-cluster-pattern)).
- For internal gRPC/HTTP services: consider Cilium's `CiliumNetworkPolicy` with mutual authentication, or sidecar-based mTLS if a service mesh is deployed.
- Document the mTLS approach (cert-manager, CNPG-native, or mesh) in a comment near the relevant resource.

### Certificates — Use cert-manager ClusterIssuer

**All TLS certificates must be issued by cert-manager using the cluster's `ClusterIssuer`**, not self-signed ad-hoc certs.

The cluster CA issuer is: `${TALOS_CLUSTER_NAME}-ca-issuer` (kind: `ClusterIssuer`)

Standard patterns:

```yaml
# Ingress — annotation-driven (preferred)
annotations:
  cert-manager.io/cluster-issuer: ${TALOS_CLUSTER_NAME}-ca-issuer
  cert-manager.io/common-name: service.${CLUSTER_EXTERNAL_DOMAIN}

# Explicit Certificate resource (for non-ingress TLS, e.g. database server certs)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <component>-server-cert
spec:
  secretName: <component>-server-cert
  usages:
    - server auth
  dnsNames:
    - <service>.<namespace>
    - <service>.<namespace>.svc
    - <service>.<namespace>.svc.cluster.local
  issuerRef:
    name: ${TALOS_CLUSTER_NAME}-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
  secretTemplate:
    labels:
      cnpg.io/reload: ""  # Add reload labels as needed by the consuming component
```

Always add the `cnpg.io/reload: ""` label (or equivalent) so that cert rotation is handled automatically by the consuming component's reload controller.

### Resource Sizing — Small to Medium Clusters

Scale deployments conservatively. The cluster runs on small/medium bare-metal nodes:

| Tier | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------|-------------|-----------|----------------|--------------|
| Critical infra (Cilium, ArgoCD) | 100–200m | 1000–2000m | 128–256Mi | 512Mi–1Gi |
| Standard services (Gitea, Traefik) | 100–500m | 1000–2000m | 128–512Mi | 512Mi–1Gi |
| Background/lightweight | 10–50m | 200–500m | 32–64Mi | 128–256Mi |

- Always set **both** `requests` and `limits`.
- Set `replicas: 1` by default. Scale up only when HA is explicitly needed.
- Use `PriorityClass` — assign `cluster-services` priority class to infrastructure workloads.
- Add `tolerations` for control-plane nodes if the workload needs to schedule there.

### Additional Best Practices

- **Health probes**: Always add `livenessProbe`, `readinessProbe`, and ideally `startupProbe`. Use `httpGet` over `exec` where possible.
- **Pod Disruption Budgets**: Add a `PodDisruptionBudget` for any workload with `replicas >= 2`.
- **Horizontal Pod Autoscaler**: Add an `HorizontalPodAutoscaler` for stateless workloads that may scale, setting conservative min/max replicas.
- **Ingress via Traefik**: All HTTP/HTTPS workloads must use the cluster's Traefik ingress with a cert-manager annotation. Never expose services directly via `NodePort` or `LoadBalancer` unless there is a specific networking reason.
- **DNS via external-dns**: Annotate Ingress resources with `external-dns.alpha.kubernetes.io/hostname` so DNS records are automatically managed.
- **Secret hygiene**: Store sensitive values in Kubernetes `Secret` objects. Never embed credentials in `ConfigMap`, Helm values files, or `.env` files committed to the repo.
- **Reloader**: Annotate `Deployment`/`StatefulSet` resources with `reloader.stakater.com/auto: "true"` so they restart automatically when referenced `ConfigMap`/`Secret` objects change.

---

## CNPG Database Cluster Pattern

Use this pattern whenever a new PostgreSQL database is needed. CNPG (CloudNativePG) is the cluster's standard database operator.

### Overview

CNPG clusters should:
- Use cert-manager certificates for both server TLS and client mTLS
- Enforce `hostssl` with `clientcert=verify-full` (mTLS) in `pg_hba`
- Have scheduled VolumeSnapshot backups
- Use the cluster's Longhorn snapshot storage class
- Set resource requests/limits appropriate for the workload

### Required Files

For a new CNPG cluster named `<app>-sql`:

| File | Purpose |
|------|---------|
| `<component>CnpgCluster.yaml` | The `Cluster`, `ScheduledBackup`, cert-manager `Certificate`/`Issuer` resources |
| `<component>CnpgArgoApp.yaml` | ArgoCD `Application` that deploys the cluster (project: `cluster-services`) |

### Certificate Setup

CNPG requires three certificate types. Use the following pattern:

```yaml
# 1. Server TLS cert (issued by cluster CA)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <app>-sql-server-cert
spec:
  secretName: <app>-sql-server-cert
  usages:
    - server auth
  dnsNames:
    - <app>-sql-rw
    - <app>-sql-rw.<namespace>
    - <app>-sql-rw.<namespace>.svc
    - <app>-sql-r
    - <app>-sql-r.<namespace>
    - <app>-sql-r.<namespace>.svc
    - <app>-sql-ro
    - <app>-sql-ro.<namespace>
    - <app>-sql-ro.<namespace>.svc
  issuerRef:
    name: ${TALOS_CLUSTER_NAME}-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
  secretTemplate:
    labels:
      cnpg.io/reload: ""
---
# 2. Client CA (self-signed, because CNPG manages its own client cert chain)
#    Note: CNPG cannot use the cluster CA for client certs due to how it validates
#    client identity. A dedicated self-signed CA is required.
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: <app>-cnpg-selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <app>-cnpg-client-ca
spec:
  isCA: true
  commonName: <app>-cnpg-client-ca
  secretName: <app>-cnpg-client-ca-key-pair
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: <app>-cnpg-selfsigned-issuer
    kind: Issuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: <app>-cnpg-client-ca-issuer
spec:
  ca:
    secretName: <app>-cnpg-client-ca-key-pair
---
# 3. Application client cert (issued by the client CA above)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <app>-cnpg-client-cert
spec:
  secretName: <app>-cnpg-client-cert
  usages:
    - client auth
  commonName: ${APP_PSQL_USERNAME}
  issuerRef:
    name: <app>-cnpg-client-ca-issuer
    kind: Issuer
    group: cert-manager.io
---
# 4. Streaming replica cert (issued by the client CA)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <app>-cnpg-streaming-replica-cert
spec:
  secretName: <app>-cnpg-streaming-replica-cert
  usages:
    - client auth
  commonName: streaming_replica
  issuerRef:
    name: <app>-cnpg-client-ca-issuer
    kind: Issuer
    group: cert-manager.io
```

> **Important**: The `clientCASecret` in the CNPG `Cluster` spec must reference the **CA secret** (`<app>-cnpg-client-ca-key-pair`), not the client leaf certificate. The CA secret is what CNPG uses to verify incoming client certs.

### Cluster Spec

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <app>-sql
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Deploy after certificates (sync wave 1)
spec:
  instances: 2          # Minimum for HA; use 3+ for zero-downtime failover
  imageName: ghcr.io/cloudnative-pg/postgresql:${APP_PSQL_VERSION}

  # Resource sizing (adjust per workload)
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

  storage:
    size: ${APP_PSQL_SIZE}
    storageClass: pvckey-2replica-retained-backedup-ssd-cp

  backup:
    volumeSnapshot:
      className: longhorn-snapshot
      snapshotOwnerReference: backup

  certificates:
    serverTLSSecret: <app>-sql-server-cert
    serverCASecret: <app>-sql-server-cert
    clientCASecret: <app>-cnpg-client-ca-key-pair    # Must be the CA secret, not leaf cert
    replicationTLSSecret: <app>-cnpg-streaming-replica-cert

  # Enable monitoring (if Prometheus is deployed)
  # monitoring:
  #   enablePodMonitor: true

  affinity:
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule

  postgresql:
    pg_hba:
      - hostssl app ${APP_PSQL_USERNAME} all scram-sha-256 clientcert=verify-full
      # Note: use md5 if the client application does not support scram-sha-256 over mTLS
      # e.g. Gitea < 10.2.0 requires: hostssl app <user> all md5 clientcert=verify-full
```

### Backup Schedule

Always pair a `ScheduledBackup` with every CNPG cluster:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: <app>-sql-backup
  annotations:
    argocd.argoproj.io/sync-wave: "50"  # Deploy late so CSI Snapshot CRDs are available
spec:
  schedule: "0 0 0 * * *"  # Daily at midnight
  method: volumeSnapshot
  backupOwnerReference: cluster
  cluster:
    name: <app>-sql
```

### Sync Wave Order

For CNPG-backed applications, use these sync waves to ensure correct ordering:

| Wave | Resource |
|------|---------|
| `0` (default) | Namespace, cert-manager `Issuer`/`Certificate` resources |
| `2` | CNPG `Cluster` (depends on certificates) |
| `5` | Application that consumes the database |
| `50` | `ScheduledBackup` (depends on CSI Snapshot CRDs) |

---

## Important Notes

- `rendered/` is gitignored — always regenerate via render-overlay.sh
- The bootstrap uses a temporary git-bootstrap-server pod before Gitea is ready
- Shell scripts use `set -euo pipefail` — strict error handling
- All env vars use `export` for shell sourcing and envsubst compatibility
- render-overlay.sh is zsh, cluster-bootstrap.sh is bash

## Copilot Coding Agent — Working Instructions

These instructions apply whenever the Copilot Coding Agent picks up an issue in this repository.

### Before Writing Any Code

1. **Read the issue carefully.** Identify every explicit requirement and any implicit constraints (e.g. "don't break existing clusters").
2. **Ask clarifying questions first.** If any requirement is ambiguous — or if fulfilling it would require touching files not mentioned in the issue — post a comment on the issue asking for clarification **before** opening a pull request or writing code. Wait for a response. Do not guess.
3. **Acknowledge scope.** Briefly summarise in an issue comment what you plan to change and why, so the requester can correct misunderstandings early.

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
