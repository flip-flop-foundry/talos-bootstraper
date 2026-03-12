# CSI Snapshot Controller

## What it does

The [CSI Snapshot Controller](https://github.com/kubernetes-csi/external-snapshotter) installs the Kubernetes `VolumeSnapshot`, `VolumeSnapshotContent`, and `VolumeSnapshotClass` CRDs and the associated controller. It is the standard Kubernetes mechanism for taking point-in-time snapshots of persistent volumes.

## Why it was added

CNPG `ScheduledBackup` resources use `method: volumeSnapshot` to back up PostgreSQL data. This requires the CSI snapshot CRDs and controller to be present in the cluster. Longhorn also uses `VolumeSnapshotClass` for snapshot management.

## Dependencies

None — the CSI snapshot controller is a foundational infrastructure component with no dependencies on other components in this repository.

## Dependents

- **cnpg** — all CNPG `ScheduledBackup` resources use `volumeSnapshot` method and depend on the snapshot CRDs and controller being available.
- **longhorn** — uses `VolumeSnapshotClass` resources for Longhorn-native snapshot operations.

## User Guide

### Checking snapshot CRD availability

```bash
kubectl get crd | grep snapshot
```

Expected output includes:
- `volumesnapshotclasses.snapshot.storage.k8s.io`
- `volumesnapshotcontents.snapshot.storage.k8s.io`
- `volumesnapshots.snapshot.storage.k8s.io`

### Listing volume snapshots

```bash
kubectl get volumesnapshot -A
kubectl get volumesnapshotcontent -A
```

### Why ScheduledBackup uses sync wave 50

CNPG `ScheduledBackup` resources are deployed at ArgoCD sync wave `50` (late) to ensure the CSI snapshot CRDs are fully established before the backup resource is created. This avoids a race condition during initial cluster bootstrap.
