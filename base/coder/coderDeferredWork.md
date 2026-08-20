# Coder — Deferred Work

Tracked follow-ups that are intentionally out of scope for the initial Coder
deployment. Each item is safe to defer; none blocks a working deployment.

## Automation of CI credential wiring

- **Remove the manual step of wiring `CODER_URL` + `CODER_SESSION_TOKEN`.**
  Today an admin must create a Coder API token and add `CODER_URL` and
  `CODER_SESSION_TOKEN` as Gitea repo secrets before the "Push Coder Templates"
  workflow can run. Investigate provisioning a dedicated Coder service account +
  token automatically during bootstrap (e.g. via the same Job that seeds other
  secrets) and injecting it into Gitea as an Actions secret through the Gitea
  API, so template pushes work with zero manual steps.

## Use Gitea as the identity/user database

- **Automate setup of using Gitea as the user database**, and research whether
  this can make Git actions inside Coder workspaces more seamless. If Coder and
  the workspaces authenticate against Gitea (OAuth/OIDC via Gitea), workspaces
  could get pre-authenticated Git access to the cluster's own repos without the
  user manually configuring credentials. Scope: a Gitea OAuth2 application for
  Coder, `CODER_OAUTH2_*` (generic OIDC) wiring, and an in-workspace Git
  credential helper.

## Workspace CPU architecture

- The workspace template hardcodes `arch = "amd64"`. On mixed or arm64 Talos
  clusters this must be adjusted. Consider a `coder_parameter` letting the user
  pick the architecture, or deriving it from a node selector.

## Postgres driver TLS env assumption

- The control plane relies on the database driver merging libpq `PG*` env vars
  (`PGSSLMODE=verify-full`, `PGSSLCERT`, `PGSSLKEY`, `PGSSLROOTCERT`) for TLS
  parameters absent from `CODER_PG_CONNECTION_URL`. This mirrors Gitea's proven
  setup. If a future Coder release changes its Postgres driver behaviour,
  fall back to composing a full DSN (with `sslmode`/`sslcert`/... query params)
  in a PreSync Job instead.

## In-workspace editor

- The template starts the Coder agent but does not install/expose an IDE
  `coder_app` (e.g. code-server / JetBrains Gateway). Add one once the preferred
  editor for the dev image is decided. Any `coder_app` must set
  `subdomain = true`: path-based apps are disabled cluster-wide
  (`CODER_DISABLE_PATH_APPS=true`), so an app without a subdomain will not be
  reachable. Subdomain apps are served under `*.${CODER_DOMAIN_NAME}` via the
  wildcard ingress.

## Coder CLI install supply-chain hardening

- The template-push workflow installs the Coder CLI via
  `curl -fsSL https://coder.com/install.sh | sh -s -- --version ${CODER_IMAGE_TAG}`.
  The version is pinned to the control-plane image tag, but the script and the
  downloaded binary are not checksum-verified. Harden by pinning `install.sh` to
  a known-good release and verifying the CLI binary's published SHA256 (or vendor
  the CLI into a runner image) before running it in CI.


## Automate setup of coder-owner-bootstrap

- Use logic similar to the Longhorn credentials setup to seed the first Coder
  owner from the `coder-owner-bootstrap` secret automatically, instead of the
  current manual `coder server create-admin-user` step.

## Set hostUsers: false on Coder pods (user namespaces)

We want Coder pods to run with `hostUsers: false` for user-namespace isolation
(https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/). Neither
the control plane nor the workspace pods can get it inline today:

- **Control plane (Helm)** — the `oci://ghcr.io/coder/chart/coder` chart only
  exposes `coder.podSecurityContext` (rendered as `spec.securityContext`), while
  `hostUsers` is a pod-spec sibling of `securityContext`. There is no pod-spec
  passthrough value, so it cannot be set via `coderValues.yaml`. Per project
  policy we do not add a post-renderer for this.
- **Workspace pods (Terraform)** — the pod in `templates/k8s-dev-image/main.tf`
  is a `kubernetes_pod` resource, and the hashicorp/kubernetes provider does not
  yet expose the pod-spec `hostUsers` field:
  - https://github.com/hashicorp/terraform-provider-kubernetes/issues/2818
  - https://github.com/hashicorp/terraform-provider-kubernetes/pull/2828

- Options once the fields land (or if we revisit sooner):
  - Control plane: upstream the `hostUsers` value into the Coder chart, or wait
    for the chart to add it.
  - Workspaces: bump the provider and add `host_users = false` to the pod `spec`
    directly, or convert the pod to a `kubernetes_manifest` resource (accepts
    arbitrary fields, but handles values only known at apply time — the Coder
    agent token / init script — poorly; validate on a live cluster first).
  - Both: enforce it cluster-side via a mutating admission webhook (e.g. Kyverno)
    that injects `spec.hostUsers: false` on Coder pods, independent of the chart
    and the Terraform provider.