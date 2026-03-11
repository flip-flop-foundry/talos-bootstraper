# Longhorn

## What it does

[Longhorn](https://longhorn.io/) is a cloud-native distributed block storage system for Kubernetes. It provides persistent volumes with built-in replication, snapshotting, and backup capabilities — all managed through Kubernetes custom resources.

This component installs the Longhorn system and configures:

- **Storage classes** for different replication and retention profiles
- **Snapshot classes** for CSI-based volume snapshots
- **Backup target** credentials for off-cluster backup storage
- **Auto-disk discovery** for worker nodes

## Why it was added

The cluster runs on bare-metal nodes without a cloud storage backend. Longhorn provides replicated, resilient persistent storage that survives individual node failures and supports scheduled backups via the CSI snapshot mechanism.

## Dependencies

- **csi-snapshot-controller** — Longhorn uses `VolumeSnapshotClass` resources that require the CSI snapshot CRDs and controller.

## Dependents

- **cnpg** — all CNPG database clusters use Longhorn storage classes for their persistent volumes and Longhorn snapshot classes for backups.
- **gitea** — Gitea's CNPG database uses Longhorn-backed storage.

## User Guide

### Accessing the Longhorn dashboard

The Longhorn dashboard is exposed via a Traefik `IngressRoute`. The URL is configured per cluster. Access requires authentication via a `Secret`-backed BasicAuth middleware.

### Checking volume health

```bash
kubectl -n longhorn-system get volumes.longhorn.io
```

Or use the Longhorn UI for a visual overview.

### Storage classes

The cluster defines several storage classes for different use cases:

| Storage Class | Replicas | Retain Policy | Use Case |
|---------------|----------|---------------|---------|
| `pvckey-2replica-retained-backedup-ssd-cp` | 2 | Retain | Database volumes (CNPG) |

Check the `storage-classes.yaml` file for the full list.

### Backup configuration

Backup targets (S3, NFS, etc.) are configured via `LONGHORN_BACKUP_TARGET` in the overlay `.env` file. Credentials are stored in a Kubernetes `Secret` (`defaultBackupTargetCredentials.yaml`).

### Disk auto-discovery

The `autoDiscoverDisksJob.yaml` Kubernetes `Job` runs on each worker node during bootstrap to discover and configure available disks for Longhorn. Disks are identified based on the `LONGHORN_DISK_*` variables in the overlay `.env` file.
