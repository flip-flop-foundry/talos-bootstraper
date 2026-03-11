# Cluster-Wide Resources

## What it does

This component contains cluster-scoped Kubernetes resources that do not belong to any specific application namespace. Currently this includes:

- **`priority-classes.yaml`** — defines `PriorityClass` objects used to assign scheduling priority to cluster infrastructure workloads.

## Why it was added

Several cluster infrastructure workloads (Cilium, ArgoCD, etc.) need to be scheduled preferentially over regular application workloads. Kubernetes `PriorityClass` objects provide this mechanism. Having them in a dedicated component keeps them separate from application-level concerns.

## Dependencies

None — this component has no dependencies on other components in this repository.

## Dependents

Any component that references a `PriorityClass` defined here depends on this component being deployed first. In practice, ArgoCD sync waves ensure the `PriorityClass` objects are created early in the bootstrap process.

## User Guide

### Available priority classes

| PriorityClass | Value | Use Case |
|---------------|-------|---------|
| `cluster-services` | High | Core infrastructure pods (Cilium, ArgoCD, cert-manager, etc.) |

To assign a priority class to a workload, add to the pod spec:

```yaml
spec:
  priorityClassName: cluster-services
```
