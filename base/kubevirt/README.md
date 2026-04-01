# KubeVirt

## What it does

KubeVirt extends Kubernetes with virtualization capabilities, allowing you to run and manage traditional virtual machines (VMs) alongside container workloads. It deploys a set of controllers (`virt-api`, `virt-controller`, `virt-handler`) that enable creating, scheduling, and managing VMs using standard Kubernetes APIs and resources such as `VirtualMachine` and `VirtualMachineInstance`.

## Why it was added

KubeVirt enables running legacy or non-containerisable workloads as VMs within the same Kubernetes cluster used for containerised services. This avoids maintaining a separate hypervisor infrastructure and allows VMs to benefit from Kubernetes scheduling, networking (via Cilium), and storage (via Longhorn).

## How it is deployed

KubeVirt does **not** have an official Helm chart. The deployment consists of two parts:

1. **Operator** — deployed during cluster bootstrap (`cluster-bootstrap.sh`) by applying the upstream release manifest directly:
   ```bash
   kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
   ```
   This step is idempotent and only runs when the kubevirt component is rendered (not in `EXCLUDED_BASE`) and the operator is not yet present.

2. **KubeVirt CR** — managed by an ArgoCD Application (`kubevirtArgoApp.yaml`) that deploys the `KubeVirt` custom resource from the Gitea repository. This CR controls the actual KubeVirt configuration (feature gates, tolerations, networking defaults).

## Enabling KubeVirt

KubeVirt is **excluded by default** in the example overlays. To enable it:

1. Remove `"kubevirt"` from the `EXCLUDED_BASE` array in your overlay's `.env` file.
2. Ensure `KUBEVIRT_VERSION` and `KUBEVIRT_NAMESPACE` are exported (they are pre-defined in the example `.env` files).
3. Re-render: `./adminTasks/render-overlay.sh overlays/<cluster>/<cluster>.env`
4. For new clusters, `cluster-bootstrap.sh` handles operator deployment automatically.
5. For existing clusters, manually deploy the operator first:
   ```bash
   source overlays/<cluster>/<cluster>.env
   kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
   ```
   Then apply the ArgoCD Application:
   ```bash
   kubectl apply -f rendered/<cluster>/kubevirt/kubevirtArgoApp.yaml
   ```

## Upgrading

1. Update `KUBEVIRT_VERSION` in your overlay's `.env` file.
2. Re-render the overlay.
3. Apply the new operator version:
   ```bash
   kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
   ```
4. ArgoCD will automatically sync the updated KubeVirt CR.

## Talos-specific notes

The existing Talos machine configuration (`base/talos/talosPatchConfig.yaml`) already includes settings that support KubeVirt:

- **`vfio_pci`** kernel module — enables PCI device passthrough for GPU/NIC passthrough to VMs.
- **`vm.nr_hugepages: "1024"`** — pre-allocates hugepages for VM memory performance.
- **KVM support** — Talos Linux includes KVM kernel support by default (`kvm`, `kvm_intel`, `kvm_amd` are compiled in).

Hardware virtualization (Intel VT-x or AMD-V) must be enabled in the node BIOS/UEFI.

## Dependencies

None beyond standard cluster infrastructure. KubeVirt uses:
- Kubernetes API for scheduling and management
- Node-level KVM for hardware virtualization
- Cilium for pod/VM networking (masquerade mode by default)

## Dependents

None currently.

## User Guide

### Verifying the installation

```bash
# Check operator status
kubectl get pods -n kubevirt

# Check KubeVirt CR status
kubectl get kubevirt -n kubevirt -o yaml

# All components should show phase "Deployed"
kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.phase}'
```

### Creating a VM

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: example-vm
spec:
  running: true
  template:
    spec:
      domain:
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
        resources:
          requests:
            memory: 1Gi
      volumes:
        - name: rootdisk
          containerDisk:
            image: quay.io/kubevirt/cirros-container-disk-demo
```

### Managing VMs

```bash
# Install virtctl CLI for VM management
export VERSION=$(kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.targetKubeVirtVersion}')
curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64
chmod +x virtctl

# Start/stop VMs
./virtctl start <vm-name>
./virtctl stop <vm-name>

# Console access
./virtctl console <vm-name>
```

### Future enhancements

- **CDI (Containerized Data Importer)** — for importing VM disk images and managing DataVolumes. Can be added as a separate component.
- **Multus** — for attaching VMs to additional networks (bridge, SR-IOV).
- **Snapshot/restore** — KubeVirt supports VM snapshots via the CSI snapshot controller already deployed in this cluster.
