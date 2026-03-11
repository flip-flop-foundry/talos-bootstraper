# Spegel

## What it does

[Spegel](https://spegel.dev/) (Swedish for "mirror") is a peer-to-peer OCI image mirror. It runs as a DaemonSet on every node and allows nodes to pull container images directly from each other rather than always fetching from external registries. When a node has already pulled an image, other nodes in the cluster can retrieve it locally, significantly reducing image pull times — especially for new nodes joining an existing cluster.

Spegel works by writing per-registry mirror configuration into `/etc/containerd/certs.d` on each node, so containerd transparently routes image pulls through the local Spegel mirror first, falling back to the upstream registry on cache miss.

## Why it was added

Adding new nodes to the cluster was slow because every container image had to be downloaded from external registries on each node independently. Spegel enables P2P image distribution within the cluster so that a new node can pull most images from its peers rather than the internet.

See: [Speed up deployment of new nodes with spegel](https://github.com/flip-flop-foundry/talos-bootstraper/issues).

## Talos-specific configuration

Talos does not read `/etc/containerd/certs.d` by default. A `machine.files` patch in `base/talos/talosPatchConfig.yaml` drops a CRI config fragment at `/etc/cri/conf.d/20-spegel-registry.part` that configures the containerd CRI plugin to load per-registry configs from that directory. Without this patch, Spegel's mirror configurations are silently ignored by containerd.

## Security

Access to the Spegel registry is restricted at two layers:

1. **Containerd mirror config** — mirror configs are only written to nodes running the Spegel DaemonSet, so no external client can discover the registry.
2. **CiliumNetworkPolicy** (`spegelNetworkPolicy.yaml`) — restricts all ingress to Spegel pods (registry 5000, router 5001, metrics 9090, cleanup probe 8080) to `fromEntities: cluster` only. Egress allows `world` (upstream registries for cache misses) and `cluster` (DNS, API server).

## Dependencies

- **nidhogg** — gates general pod scheduling on new nodes until Spegel is ready, ensuring the image cache is available before workloads attempt to pull images.
- **talos** — requires a containerd CRI config patch (`talosPatchConfig.yaml`) so containerd loads per-registry mirror configs from `/etc/containerd/certs.d`.

## Dependents

- **nidhogg** — watches the Spegel DaemonSet and removes the node taint only once Spegel is ready on that node.

## User Guide

### Checking Spegel status

```bash
# Check DaemonSet rollout
kubectl -n spegel get daemonset spegel

# View logs on a specific node's Spegel pod
kubectl -n spegel logs -l app.kubernetes.io/name=spegel --tail=50
```

### Verifying mirror configuration on a node

SSH to any node (via `talosctl`) and check that containerd is loading the mirror config:

```bash
# Should show config_path = "/etc/containerd/certs.d"
cat /etc/cri/conf.d/20-spegel-registry.part

# Should show per-registry mirror entries written by Spegel
ls /etc/containerd/certs.d/
```

### Metrics

Spegel exposes Prometheus metrics on port `9090`. If a Prometheus stack is deployed, metrics can be scraped from each DaemonSet pod.
