# Reloader

## What it does

[Reloader](https://github.com/stakater/Reloader) is a Kubernetes controller that watches `ConfigMap` and `Secret` objects for changes and automatically triggers a rolling restart of any `Deployment`, `StatefulSet`, or `DaemonSet` that references them.

Without Reloader, pods keep the stale configuration in memory even after the underlying `Secret` or `ConfigMap` is updated (e.g. after a cert-manager certificate renewal). Reloader closes this gap by detecting the change and issuing a rolling restart automatically.

## Why it was added

Several components in this cluster consume secrets that are rotated automatically (TLS certificates issued by cert-manager, CNPG credentials, etc.). Reloader ensures those components pick up the new values without manual intervention or downtime.

## Dependencies

None — Reloader has no dependencies on other components in this repository.

## Dependents

Any component that annotates its `Deployment`/`StatefulSet` with `reloader.stakater.com/auto: "true"` implicitly depends on Reloader. In this repository those include:

- **gitea** — restarts on certificate or secret rotation
- **external-dns** — restarts on TSIG secret rotation

## User Guide

### Enabling automatic restarts

Add the following annotation to any `Deployment` or `StatefulSet` that should restart when a referenced `Secret` or `ConfigMap` changes:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

Reloader will watch **all** `Secret` and `ConfigMap` objects referenced by that workload (via `envFrom`, `env.valueFrom`, or volume mounts).

### Triggering a restart after a certificate renewal

cert-manager renews TLS certificates automatically. As long as the consuming `Deployment` or `StatefulSet` carries the `reloader.stakater.com/auto: "true"` annotation, the restart happens without any manual action.

To verify Reloader is running and has detected a change, check its logs:

```bash
kubectl -n <reloader-namespace> logs -l app.kubernetes.io/name=reloader --tail=50
```
