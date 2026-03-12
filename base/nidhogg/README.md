# Nidhogg

## What it does

[Nidhogg](https://github.com/pelotech/nidhogg) is a Kubernetes controller that taints new nodes with a `NoSchedule` taint until a specified DaemonSet is ready on that node. In this cluster it watches the Spegel DaemonSet: when a new node joins, Nidhogg immediately applies the taint `nidhogg.uswitch.com/spegel.spegel:NoSchedule`, which prevents general workloads from being scheduled on that node until Spegel has started and the image cache is available.

Once Spegel becomes ready on the node (its pod passes its readiness probe), Nidhogg removes the taint and normal scheduling resumes.

Spegel's DaemonSet tolerates all `NoSchedule` taints (including the Nidhogg taint) so it can start on the node while the taint is still present.

## Why it was added

Without Nidhogg, workloads can be scheduled on a new node before Spegel is running there, forcing those pods to pull images from external registries even though the cluster already has the images cached. Nidhogg closes this race condition.

See: [Speed up deployment of new nodes with spegel](https://github.com/flip-flop-foundry/talos-bootstraper/issues).

## Dependencies

- **spegel** — Nidhogg is configured to watch the Spegel DaemonSet. It has no value without Spegel.

## Dependents

None directly, but all other workloads in the cluster indirectly benefit: they are guaranteed not to be scheduled on a node until Spegel is ready.

## User Guide

### Checking taint status on a node

```bash
# List node taints — a new node should show the Nidhogg taint while Spegel is starting
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Once Spegel is ready, the taint should be absent
kubectl describe node <node-name> | grep -A5 Taints
```

### Checking Nidhogg controller logs

```bash
kubectl -n nidhogg logs -l app.kubernetes.io/name=nidhogg --tail=50
```

### Configuration

Nidhogg is configured in `nidhoggHelmValues.yaml` to:
- Watch the DaemonSet `spegel` in namespace `${SPEGEL_NAMESPACE}`
- Wait 5 seconds after Spegel becomes ready before removing the taint (avoids a scheduling race)
- Run 2 replicas for controller availability
- Run on control-plane nodes (via toleration)
