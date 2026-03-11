# Metrics Server

## What it does

[Metrics Server](https://github.com/kubernetes-sigs/metrics-server) is a cluster-wide aggregator of resource usage data. It collects CPU and memory metrics from Kubelets and exposes them via the Kubernetes Metrics API (`metrics.k8s.io`).

These metrics power `kubectl top`, Horizontal Pod Autoscalers (HPAs), and Vertical Pod Autoscalers (VPAs).

## Why it was added

`kubectl top nodes` / `kubectl top pods` and HPAs require the Metrics API to be available. Metrics Server is the standard, lightweight way to provide this in a bare-metal cluster (where a cloud provider metrics adapter is not available).

## Dependencies

None — Metrics Server has no dependencies on other components in this repository.

## Dependents

Any workload that uses a `HorizontalPodAutoscaler` or `VerticalPodAutoscaler` depends on Metrics Server being available.

## User Guide

### Checking node and pod resource usage

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage across all namespaces
kubectl top pods -A

# Pod resource usage in a specific namespace
kubectl top pods -n <namespace>
```

### Verifying Metrics Server is working

```bash
kubectl -n kube-system get apiservice v1beta1.metrics.k8s.io
```

The `AVAILABLE` column should show `True`.

### Troubleshooting

If `kubectl top` returns "Metrics API not available":

```bash
kubectl -n kube-system logs -l k8s-app=metrics-server --tail=50
```

On Talos, ensure the Kubelet serving certificate is configured correctly (the `--kubelet-insecure-tls` flag may be needed if the Kubelet is using a self-signed certificate that Metrics Server cannot verify).
