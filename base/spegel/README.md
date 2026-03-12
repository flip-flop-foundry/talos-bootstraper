# Spegel

## What it does

[Spegel](https://spegel.dev/) (Swedish for "mirror") is a peer-to-peer OCI image mirror. It runs as a DaemonSet on every node and allows nodes to pull container images directly from each other rather than always fetching from external registries. When a node has already pulled an image, other nodes in the cluster can retrieve it locally, significantly reducing image pull times — especially for new nodes joining an existing cluster.

Spegel works by writing per-registry mirror configuration (as `hosts.toml` files) into `/var/etc/cri/conf.d` on each node, so containerd transparently routes image pulls through the local Spegel mirror first, falling back to the upstream registry on cache miss.

## Why it was added

Adding new nodes to the cluster was slow because every container image had to be downloaded from external registries on each node independently. Spegel enables P2P image distribution within the cluster so that a new node can pull most images from its peers rather than the internet.

See: [Speed up deployment of new nodes with spegel](https://github.com/flip-flop-foundry/talos-bootstraper/issues).

## Talos-specific configuration

Talos Linux requires two `machine.files` patches in `base/talos/talosPatchConfig.yaml`:

1. **`/var/etc/cri/conf.d/20-spegel.part`** — disables `discard_unpacked_layers` (Talos enables this by default, which prevents Spegel from serving cached image layers to peers).
2. **`/var/etc/cri/conf.d/20-spegel-registry.part`** — sets `config_path = "/var/etc/cri/conf.d"` in the containerd CRI plugin, so containerd reads the mirror `hosts.toml` files that Spegel writes into subdirectories of `/var/etc/cri/conf.d`.

`/var/etc/cri/conf.d/` is the writable directory Talos uses for containerd CRI configuration fragments. Spegel's `containerdRegistryConfigPath` is set to this same path.

## Security

Access to the Spegel registry is restricted at two layers:

1. **Containerd mirror config** — mirror configs are only written to nodes running the Spegel DaemonSet, so no external client can discover the registry.
2. **CiliumNetworkPolicy** (`spegelNetworkPolicy.yaml`) — restricts all ingress to Spegel pods (registry 5000, router 5001, metrics 9090, cleanup probe 8080) to `fromEntities: cluster` only. Egress allows `world` (upstream registries for cache misses) and `cluster` (DNS, API server).

## Dependencies

- **nidhogg** — gates general pod scheduling on new nodes until Spegel is ready, ensuring the image cache is available before workloads attempt to pull images.
- **talos** — requires two containerd CRI config patches (`talosPatchConfig.yaml`): one to disable layer discarding, and one to set the registry config path to `/var/etc/cri/conf.d`.

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

Talos nodes do not support SSH. Use `talosctl` to inspect files directly on the node:

```bash
# Verify the CRI config fragments are in place
talosctl read /var/etc/cri/conf.d/20-spegel.part --nodes <node-ip>
talosctl read /var/etc/cri/conf.d/20-spegel-registry.part --nodes <node-ip>

# List per-registry mirror configs written by Spegel
talosctl ls /var/etc/cri/conf.d/ --nodes <node-ip>
```

Replace `<node-ip>` with the IP of the node you want to inspect.

### Metrics

Metrics are currently disabled. `serviceMonitor.enabled` and `grafanaDashboard.enabled` are both set to `false` in `spegelHelmValues.yaml`, and port 9090 is not exposed by the CiliumNetworkPolicy. To enable metrics scraping in future, set `serviceMonitor.enabled: true` in the Helm values and add port 9090 back to `spegelNetworkPolicy.yaml`.
