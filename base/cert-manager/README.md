# cert-manager

## What it does

[cert-manager](https://cert-manager.io/) is a Kubernetes certificate management controller. It automates the provisioning, renewal, and rotation of TLS certificates using `Certificate`, `Issuer`, and `ClusterIssuer` custom resources.

This component also installs the **cert-manager CSI driver** (for mounting certificates directly into pods) and the **trust-manager** bundle (for distributing the cluster CA to workloads that need to trust it).

The cluster CA issuer (`${TALOS_CLUSTER_NAME}-ca-issuer`) is the root of trust for all internal TLS in this cluster.

## Why it was added

All internal service-to-service communication in the cluster uses TLS. cert-manager provides a single, consistent way to issue and rotate certificates for every component — removing the need to manage certificates manually.

## Dependencies

None — cert-manager is a foundational dependency that other components rely on. It has no dependencies on other components in this repository.

## Dependents

Every component that uses TLS certificates depends on cert-manager, including:

- **argocd** — repo-server TLS certificate
- **gitea** — Gitea ingress TLS and CNPG mTLS certificates
- **cnpg** — all CNPG clusters use cert-manager for server and client certificates
- **longhorn** — dashboard TLS certificate
- **traefik** — ingress TLS certificates
- **external-dns** — no direct cert dependency, but DNS records are required for ACME challenges if using Let's Encrypt issuers in the future

## User Guide

### Checking certificate status

```bash
# List all certificates across all namespaces
kubectl get certificates -A

# Describe a certificate to see renewal status
kubectl describe certificate <cert-name> -n <namespace>

# List certificate requests
kubectl get certificaterequest -A
```

### Manually triggering a certificate renewal

```bash
# Annotate the certificate to force immediate renewal
kubectl -n <namespace> annotate certificate <cert-name> \
  cert-manager.io/issuer-kind=ClusterIssuer \
  cert-manager.io/renew-before-expiry=true --overwrite
```

Or delete the existing `Secret` — cert-manager will recreate it automatically:

```bash
kubectl -n <namespace> delete secret <cert-secret-name>
```

### Trust bundle

The `certManagerTrustBundle.yaml` configures trust-manager to distribute the cluster CA certificate to all namespaces. Workloads that need to trust internal services can mount the trust bundle `ConfigMap`.
