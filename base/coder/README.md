# Coder

## What it does

Deploys the [Coder](https://coder.com) control plane — a self-hosted platform
that provisions cloud development environments (workspaces) on demand. In this
cluster, Coder gives users a ready-to-use environment for hacking on
talos-bootstrapper itself, backed by the same `k8s-dev-image` used by this
devcontainer.

The control plane runs as an ArgoCD `Application` using Coder's official OCI
Helm chart. Workspaces are Kubernetes Pods (one per user session) scheduled into
a dedicated `${CODER_WORKSPACES_NAMESPACE}` namespace with a persistent home
volume.

## Why it was added

To give operators and contributors of Talos-bootstrapper clusters a place to
code and improve talos-bootstrapper without setting up a local toolchain.

## Dependencies

- **cnpg** — provides the PostgreSQL database (`coder-sql`) that stores Coder
  state. mTLS is enforced (`scram-sha-256` + `clientcert=verify-full`).
- **cert-manager** — issues the server/client certificates for the database and
  the ingress TLS certificate.
- **reloader** — restarts the Coder deployment when the GitHub OAuth or database
  secrets change.
- **gitea-runners** — executes the "Push Coder Templates" Gitea Actions workflow.
- **longhorn** — provides the encrypted storage classes for the database
  (`nssharedkey-*`) and workspace home volumes (`pvckey-*`).

## Dependents

- None. Coder is a leaf workload.

## User Guide

### One-time admin setup (manual)

1. **GitHub OAuth (optional but recommended).** Create a GitHub OAuth app with
   callback `https://${CODER_DOMAIN_NAME}/api/v2/users/oauth2/github/callback`,
   then populate the `coder-github-oauth` secret:
   ```bash
   kubectl -n ${CODER_NAMESPACE} patch secret coder-github-oauth --type merge \
     -p '{"stringData":{"client-id":"<id>","client-secret":"<secret>"}}'
   ```
   Coder starts even before this is set (GitHub login simply stays disabled),
   thanks to the `optional: true` secret references.

2. **Break-glass owner (automated, implemented).** The `coderOwnerBootstrapJob` PostSync hook
   seeds the first Coder owner automatically once the control plane is healthy —
   username `admin`, email `admin@${CODER_DOMAIN_NAME}`, with a randomly
   generated password written back into the `coder-owner-bootstrap` secret.
   Retrieve the password with:
   ```bash
   kubectl -n ${CODER_NAMESPACE} get secret coder-owner-bootstrap \
     -o jsonpath='{.data.password}' | base64 -d; echo
   ```
   The Job is idempotent: it does nothing if an owner already exists, and reuses
   any password already stored in the secret (so the stored value stays valid
   after a database restore).

3. **Template CI credentials.** For the "Push Coder Templates" Gitea Actions
   workflow to publish workspace templates, add two secrets to the cluster
   services Gitea repo:
   - `CODER_URL` = `https://${CODER_DOMAIN_NAME}`
   - `CODER_SESSION_TOKEN` = a Coder API token (`coder tokens create`)

   > This manual step is tracked for automation in `coderDeferredWork.md`.

### Restarting after a secret change

Reloader watches the referenced secrets, so updating `coder-github-oauth`
triggers an automatic rollout. To force one manually:
```bash
kubectl -n ${CODER_NAMESPACE} rollout restart deploy/coder
```

### Connecting

Browse to `https://${CODER_DOMAIN_NAME}`. Workspaces are created from the
`k8s-dev-image` template and land in `${CODER_WORKSPACES_NAMESPACE}`.

### Notes

- Docker-in-workspace is intentionally **not** enabled; workspaces are
  unprivileged Pods.
- Workspace templates live in `templates/` and are pushed to Coder by the Gitea
  Actions workflow whenever `_rendered/coder/templates/**` changes.
- Workspace resource requests/limits (default 500m/1Gi request, 4 CPU/8Gi limit)
  are defined in the `k8s-dev-image` template and are tunable — lower them for
  small clusters if workspaces fail to schedule.
