# CloudNativePG (CNPG)

## What it does

[CloudNativePG](https://cloudnative-pg.io/) is a Kubernetes operator that manages the full lifecycle of PostgreSQL database clusters. It handles provisioning, high availability, streaming replication, automated failover, backup, and restore — all expressed as Kubernetes custom resources (`Cluster`, `ScheduledBackup`, etc.).

This directory contains the ArgoCD `Application` that deploys the **CNPG operator itself** (the controller). Individual database clusters (e.g. the Gitea database) are defined in their own component directories.

## Why it was added

Gitea (and potentially other future stateful services) require a PostgreSQL database. CNPG was chosen as the standard database operator because it integrates natively with Kubernetes, supports cert-manager for mTLS, and uses Longhorn VolumeSnapshots for backups.

## Dependencies

- **csi-snapshot-controller** — required for `ScheduledBackup` resources that use `volumeSnapshot` as the backup method.
- **reloader** — database clusters annotate their pods so that Reloader restarts them when TLS certificates are rotated.

## Dependents

- **gitea** — the Gitea Git server uses a CNPG-managed PostgreSQL cluster (`giteaCnpgCluster.yaml`) for its database.

## User Guide

### Connecting to a database cluster

Each CNPG cluster exposes three Kubernetes services:

| Service | Purpose |
|---------|---------|
| `<cluster>-rw` | Read-write (primary only) |
| `<cluster>-r` | Read (any instance) |
| `<cluster>-ro` | Read-only (replicas only) |

Application connection strings should target `<cluster>-rw.<namespace>.svc` for writes.

### Checking cluster health

```bash
kubectl -n <namespace> get cluster <cluster-name>
kubectl -n <namespace> describe cluster <cluster-name>
```

### Triggering a manual backup

```bash
kubectl -n <namespace> apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-backup
spec:
  method: volumeSnapshot
  cluster:
    name: <cluster-name>
EOF
```

### Listing backups

```bash
kubectl -n <namespace> get backup
kubectl -n <namespace> get scheduledbackup
```

### Performing a failover

```bash
kubectl cnpg promote <cluster-name> <target-pod-name> -n <namespace>
```

### Certificate rotation

Server and client TLS certificates are managed by cert-manager and rotated automatically. Because the CNPG operator monitors its own certificates via the `cnpg.io/reload: ""` label on cert-manager secrets, no manual restart is required.
