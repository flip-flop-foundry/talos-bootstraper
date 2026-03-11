# Cilium

## What it does

[Cilium](https://cilium.io/) is the cluster's CNI (Container Network Interface) plugin. It provides:

- **Pod networking** — Layer 3/4 routing between pods across nodes
- **Network policies** — eBPF-based `CiliumNetworkPolicy` enforcement
- **LoadBalancer IPs** — IP address advertisement for `LoadBalancer`-type services, either via L2 ARP announcements or BGP
- **Node-to-node encryption** — WireGuard-based transparent encryption of all pod-to-pod traffic
- **kube-proxy replacement** — Cilium replaces `kube-proxy` entirely using eBPF

## Why it was added

Cilium is chosen over simpler CNI plugins because it provides both networking and security policy enforcement in one component, with excellent performance via eBPF, and it includes a built-in LoadBalancer implementation suitable for bare-metal clusters.

## Dependencies

None — Cilium is the first component deployed in the cluster (sync wave `-50`). It has no dependencies on other components in this repository.

## Dependents

Every other component depends on Cilium being healthy because it provides pod networking and `LoadBalancer` IP allocation.

## User Guide

### LoadBalancer modes

Cilium supports two LoadBalancer advertisement modes. The mode is selected by which files are included/excluded in `EXCLUDED_BASE`:

| Mode | Included files | Excluded files |
|------|---------------|----------------|
| **L2** (default) | `ciliumL2AnnouncementPolicy.yaml`, `ciliumLoadBalancerIPPool.yaml` | BGP files |
| **BGP** | BGP files, `ciliumLoadBalancerIPPool.yaml` | `ciliumL2AnnouncementPolicy.yaml` |

See the main `CLAUDE.md` for full configuration details.

### Checking Cilium status

```bash
# Install the Cilium CLI if not already present
cilium status

# Check network connectivity
cilium connectivity test
```

### Checking BGP peers (BGP mode only)

```bash
cilium bgp peers
cilium bgp routes
```

### Checking L2 announcements (L2 mode only)

```bash
kubectl get ciliuml2announcementpolicy
kubectl get ciliumbgploadbalancerippoolpolicy
```

### Node encryption

WireGuard encryption is enabled by default. To verify:

```bash
cilium encrypt status
```
