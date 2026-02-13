#!/bin/bash

##Requirements: 
# talosctl
# helm@3
# yq
# kubectl
# curl
# jq

# Install Homebrew if not already installed,
# follow the manual steps that are prompted after. 
#/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

#brew install helm@3 yq kubernetes-cli k9s talosctl jq


## Command run example: ./adminTasks/cluster-initialSetup.sh overlays/sek8s1/sek8s1.env;

set -euo pipefail 

# ============================================================================
# ARGUMENT PARSING AND CONFIGURATION LOADING
# ============================================================================

if [ $# -ne 1 ]; then
  echo "Usage: $0 <config-file>"
  exit 1
fi

CONFIG_FILE="$1"
CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file $CONFIG_FILE not found!"
  exit 2
fi


# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ============================================================================
# ENVIRONMENT SETUP AND VALIDATION
# ============================================================================

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load logging library
# shellcheck source=./lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh" || { echo "Error: Failed to load logging.sh"; exit 1; }

# Load disk detection library
# shellcheck source=./lib/disk-detection.sh
source "$SCRIPT_DIR/lib/disk-detection.sh" || { log_error "Failed to load disk-detection.sh"; exit 1; }

# Load kubernetes utilities library
# shellcheck source=./lib/kubernetes.sh
source "$SCRIPT_DIR/lib/kubernetes.sh" || { log_error "Failed to load kubernetes.sh"; exit 1; }

export OVERLAY_DIR="$(cd "$(dirname "$CONFIG_FILE")" && pwd)"
export BASE_DIR="$(cd "$OVERLAY_DIR/../../base" && pwd)"
export RENDERED_DIR="$(cd "$OVERLAY_DIR/../.." && pwd)/rendered/$OVERLAY_NAME"
export NR_OF_CONTROL_NODES=${#TALOS_CONTROL_NODES[@]}
export TALOSCONFIG="$OVERLAY_DIR/talos/talosconfig"

log_info "Using Script Directory:  $SCRIPT_DIR"
log_info "Using Base Directory: $BASE_DIR"
log_info "Using Overlay Directory: $OVERLAY_DIR"
log_info "Using Rendered Directory: $RENDERED_DIR"
log_info "Using Talos config file: $TALOSCONFIG"

cd "$OVERLAY_DIR" || exit 1

if [ -z "$TALOS_INSTALL_IMAGE" ] || [ -z "$POD_CIDR" ] || [ -z "$SERVICE_CIDR" ]; then
  log_error "TALOS_INSTALL_IMAGE, POD_CIDR, and SERVICE_CIDR must be set in the config file."
  exit 3
fi

# ============================================================================
# NODE RESET (IF ENABLED)
# ============================================================================

# Reset nodes if TALOS_RESET_NODES is true
if [ -f "$TALOSCONFIG" ]; then
  # Loop over control nodes for Talos operations
  for NODE in "${TALOS_CONTROL_NODES[@]}"; do
    
    if [ "$TALOS_RESET_NODES" = "true" ]; then
    log_info "Checking if node \"$NODE\" is in maintenance mode..."
      if ! talosctl apply-config --insecure --nodes "$NODE" --file "$OVERLAY_DIR/talos/controlplane.yaml" --dry-run 2>&1 | grep -qi "Node is running in maintenance mode"; then
          log_warn "Node $NODE is not in maintenance mode, resetting..."
          talosctl reset --graceful=false --reboot -n "$NODE" --endpoints "$NODE"
      else
          log_success "Node $NODE is already in maintenance mode, no need to reset."
      fi
    fi

  done
fi

# ============================================================================
# DIRECTORY AND SECRETS SETUP
# ============================================================================

mkdir -p talos
mkdir -p "$RENDERED_DIR/talos"

if [ "$TALOS_OVERWRITE_CONF" = "true" ]; then
  rm -f "$OVERLAY_DIR/talos/controlplane.yaml"
  rm -f "$OVERLAY_DIR/talos/worker.yaml"
  rm -f "$RENDERED_DIR/talos/"controlplane-*.yaml
  rm -f "$RENDERED_DIR/talos/"worker-*.yaml
  rm -f talos/talosconfig
  log_warn "TALOS_OVERWRITE_CONF is true: will delete existing machineconfigs and talosconfig, if they exist."
fi

if [ "$TALOS_OVERWRITE_SECRETS" = "true" ]; then
  rm -f talos/talos-secrets.yaml
  log_warn "TALOS_OVERWRITE_SECRETS is true: will delete existing secrets, if they do exist."
fi

#set -x

if [ ! -f "$OVERLAY_DIR/talos/talos-secrets.yaml" ]; then
  log_info "Generating talos secrets"
  talosctl gen secrets -o "$OVERLAY_DIR/talos/talos-secrets.yaml"
else
  log_info "Talos secrets file already exists, skipping generation."
fi

# ============================================================================
# TALOS CONFIGURATION GENERATION
# ============================================================================

  log_info "Creating patch for Talos config..."

  envsubst < "${BASE_DIR}/talos/talosPatchConfig.yaml" > "talos/talosPatchConfigRendered.yaml"
  envsubst < "${BASE_DIR}/talos/talosPatchConfigControlplane.yaml" > "talos/talosPatchConfigControlplaneRendered.yaml"

  CONFIG_PATCH_ARGS="--config-patch @talos/talosPatchConfigRendered.yaml"
  CONFIG_PATCH_CONTROLPLANE_ARGS="--config-patch-control-plane @talos/talosPatchConfigControlplaneRendered.yaml"


log_info "Generating Talos config..."
# set -x
talosctl gen config --with-secrets "$OVERLAY_DIR/talos/talos-secrets.yaml" \
  --install-image "$TALOS_INSTALL_IMAGE" \
  --output "$OVERLAY_DIR/talos/" \
  "$TALOS_CLUSTER_NAME" "https://${TALOS_CLUSTER_ENDPOINT}:6443" \
  $CONFIG_PATCH_ARGS \
  $CONFIG_PATCH_CONTROLPLANE_ARGS \
  --force \
  --kubernetes-version ${KUBERNETES_VERSION} \
  --talos-version ${TALOS_VERSION}

rm "talos/talosPatchConfigRendered.yaml"
rm "talos/talosPatchConfigControlplaneRendered.yaml"
  # DISABLED DISABLED DISABLED, replaced by KMS only for now
  # read -rsp "Enter Talos system disk LUKS passphrase (will not be echoed): " LUKS_PASSPHRASE
  # echo
  # echo "Please make sure you have saved the Talos system disk LUKS passphrase somewhere safe. Press Enter to continue."
  # read

  # export TALOS_SYSTEMDISK_LUKS_PASSPHRASE="$LUKS_PASSPHRASE"

# ============================================================================
# TALOSCONFIG UPDATE
# ============================================================================

  log_info "Updating talosconfig context for $TALOS_CLUSTER_NAME"
  talosctl config endpoint "$TALOS_CLUSTER_ENDPOINT" --talosconfig "$TALOSCONFIG"


  # Patch the fact that talosctl is dumb about reciving a list of nodes
  TALOS_CONTROL_NODES_CSV=$(IFS=','; echo "${TALOS_CONTROL_NODES[*]}")
  export TALOS_CONTROL_NODES_CSV
  yq -i ".contexts.$TALOS_CLUSTER_NAME.nodes = (env(TALOS_CONTROL_NODES_CSV) | split(\",\"))" "$TALOSCONFIG"

# ============================================================================
# ADDITIONAL TRUSTED ROOT CAs
# ============================================================================

if [ -n "$TALOS_ADDITIONAL_TRUSTEDROOT_FILES" ]; then
  log_info "Adding additional trusted root CA certs to Talos config"
  for CERT_FILE in "${TALOS_ADDITIONAL_TRUSTEDROOT_FILES[@]}"; do
    if [ -f "$OVERLAY_DIR/$CERT_FILE" ]; then
      log_info "  Adding trusted root CA cert $CERT_FILE to $OVERLAY_DIR/talos/controlplane.yaml"
      export CA_CERT_BODY=$(cat "$OVERLAY_DIR/$CERT_FILE" | sed 's/^/    /') # Indent each line with 4 spaces for YAML block literal
      CA_NAME=$(basename "$CERT_FILE" | sed 's/\.[^.]*$//')
      export CA_NAME+="_ca"
      echo "---" >> "$OVERLAY_DIR/talos/controlplane.yaml"
      envsubst < "${BASE_DIR}/talos/trustedRootsConfigTemplate.yaml" >> "$OVERLAY_DIR/talos/controlplane.yaml"
      echo "" >> "$OVERLAY_DIR/talos/controlplane.yaml"
      
    else
      log_warn "Trusted root CA cert file $CERT_FILE not found, skipping."
    fi
  done
fi

# ============================================================================
# APPEND MANIFESTS TO CONTROL NODES
# ============================================================================

# Make sure systemVolumes.yaml are appended to controlplane.yaml
TALOS_APPEND_MANIFESTS_CONTROL_NODES+=("${BASE_DIR}/talos/systemVolumes.yaml")

# ============================================================================
# DYNAMIC DISK DETECTION AND PER-NODE CONFIG GENERATION FOR CONTROL NODES
# ============================================================================

log_info "Generating per-node configs for control nodes (disk layouts may differ)..."
for NODE in "${TALOS_CONTROL_NODES[@]}"; do
  NODE_HOSTNAME=$(echo "$NODE" | cut -d'.' -f1)  # Extract hostname from FQDN
  NODE_CONFIG_FILE="$RENDERED_DIR/talos/controlplane-${NODE_HOSTNAME}.yaml"
  
  log_info "  Creating config for node $NODE -> $NODE_CONFIG_FILE"
  
  # Copy base controlplane.yaml to node-specific file
  cp "$OVERLAY_DIR/talos/controlplane.yaml" "$NODE_CONFIG_FILE"
  
  # Detect and append disk configs for this specific node
  log_info "  Detecting disks on node $NODE..."
  DISK_CONFIGS=$(detect_node_disks "$NODE" "$TALOSCONFIG")

  if [ -n "$DISK_CONFIGS" ]; then
    log_info "  Additional disks detected on worker node $NODE, generating disk configs..."
    generate_node_disk_configs "$NODE" "$NODE_CONFIG_FILE" "$TALOS_DISK_ENCRYPTION_KMS_URL" "$TALOSCONFIG"
  else
    log_info "    No additional disks found on $NODE (only system disk detected)"
  fi

  # Append any additional manifests specified in env file
  if [ -n "$TALOS_APPEND_MANIFESTS_CONTROL_NODES" ]; then
    for MANIFEST in "${TALOS_APPEND_MANIFESTS_CONTROL_NODES[@]}"; do
      log_info "  Appending manifest $MANIFEST to $NODE_CONFIG_FILE"
      echo "---" >> "$NODE_CONFIG_FILE"
      envsubst < "$MANIFEST" >> "$NODE_CONFIG_FILE"
      echo "" >> "$NODE_CONFIG_FILE"
    done
  fi
done



# ============================================================================
# APPLY TALOS CONFIG TO CONTROL NODES
# ============================================================================

log_info "Applying Talos config to controlplane nodes"

CLUSTER_ALREADY_BOOTSTRAPPED=true
for NODE in "${TALOS_CONTROL_NODES[@]}"; do
  NODE_HOSTNAME=$(echo "$NODE" | cut -d'.' -f1)
  NODE_CONFIG_FILE="$RENDERED_DIR/talos/controlplane-${NODE_HOSTNAME}.yaml"
  
  log_info "Applying Talos config to controlplane node $NODE from $NODE_CONFIG_FILE..."

  INSECURE=""
  if ! talosctl get members --nodes "$NODE" &>/dev/null; then
    INSECURE=" --insecure"
  fi

  talosctl apply-config${INSECURE} --nodes "$NODE" --file "$NODE_CONFIG_FILE" # Have tested applying to two nodes at once, but it seems to be more reliable to apply one at a time. Maybe testing with 3+ nodes would be a good idea.


  # Wait for talosctl health to return [Preparing] for the first node
  TIMEOUT_SECONDS=${PREPARING_TIMEOUT:-300}
  START_TIME=$(date +%s)
  log_info "Waiting for node health to return [Preparing] (timeout: $TIMEOUT_SECONDS seconds)..."
  
  while true; do

    # Temporarily disable error exit to allow polling command to fail
    set +e
    set -x
    HEALTH_STATUS=$(talosctl get machinestatus --nodes "$NODE" --endpoints "$NODE" 2>&1)
    set -e
    set +x

    if echo "$HEALTH_STATUS" | grep -q "booting"; then
      log_success "Node is up and running again, can continue with bootstrap."
      CLUSTER_ALREADY_BOOTSTRAPPED=false
      break
    elif echo "$HEALTH_STATUS" | grep -q "running   true"; then
      log_success "Node is up and running again, can continue with bootstrap."
      break
    else
      log_info "Node health returned unexpected status, continuing to wait: $HEALTH_STATUS"
    fi
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
      log_error "Timeout waiting for node health to return [Preparing] after $TIMEOUT_SECONDS seconds."
      exit 4
    fi
    sleep 2
  done


done

# ============================================================================
# FETCH KUBECONFIG
# ============================================================================
log_info "Fetching kubeconfig..."
KUBECONFIG_RETRIES=5
KUBECONFIG_RETRY_DELAY=5
for attempt in $(seq 1 $KUBECONFIG_RETRIES); do
  if talosctl kubeconfig --merge --force --nodes "${TALOS_CONTROL_NODES[0]}" ~/.kube/config; then
    log_success "Kubeconfig fetched successfully."
    break
  elif [ $attempt -lt $KUBECONFIG_RETRIES ]; then
    log_warn "Attempt $attempt failed, retrying in $KUBECONFIG_RETRY_DELAY seconds..."
    sleep $KUBECONFIG_RETRY_DELAY
  else
    log_error "Failed to fetch kubeconfig after $KUBECONFIG_RETRIES attempts."
    exit 6
  fi
done

# ============================================================================
# BOOTSTRAP CLUSTER
# ============================================================================

if [ "$CLUSTER_ALREADY_BOOTSTRAPPED" = true ]; then
  log_info "Cluster already bootstrapped, skipping bootstrap step."

else
  log_info "Cluster not yet bootstrapped, proceeding with bootstrap step."
  talosctl --nodes "${TALOS_CONTROL_NODES[0]}" bootstrap

fi

# ============================================================================
# WAIT FOR KUBERNETES API
# ============================================================================

log_info "Waiting for Kubernetes API to be responsive..."
KUBECONFIG=~/.kube/config
TIMEOUT_SECONDS=${K8S_READY_TIMEOUT:-300}
START_TIME=$(date +%s)
while true; do
    # Temporarily disable error exit to allow polling command to fail
    set +e
    kubectl --kubeconfig="$KUBECONFIG" get nodes >/dev/null 2>&1
    STATUS=$?
    set -e
    if [ $STATUS -eq 0 ]; then
        log_success "Kubernetes API is responsive."
        break
    fi
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
        log_error "Timeout waiting for Kubernetes API to be responsive after $TIMEOUT_SECONDS seconds."
        exit 5
    fi
    sleep 2
done

# ============================================================================
# CSR APPROVAL WATCHER AND DEPLOYMENT
# ============================================================================

log_info "Starting CSR approval for control plane nodes..."
# Approve node CSRs for all expected nodes (max_timeout: 300s, inter_node_timeout: 120s)
approve_node_csrs 300 120 "${TALOS_CONTROL_NODES[@]}"


"$SCRIPT_DIR/cluster-bootstrap.sh" "$CONFIG_FILE"
DEPLOY_STATUS=$?

# ============================================================================
# WAIT FOR CILIUM AND DEPLOY WORKER NODES
# ============================================================================

if [ ${#TALOS_WORKER_NODES[@]} -gt 0 ]; then
  log_info "Worker nodes configured, waiting for Cilium to be ready before deploying workers..."
  
  if kubectl rollout status daemonset/cilium -n kube-system --timeout=5m; then
    log_success "Cilium is ready. Proceeding with worker node deployment..."
    
    # Generate per-node configs for worker nodes
    log_info "Generating per-node configs for worker nodes (disk layouts may differ)..."
    for NODE in "${TALOS_WORKER_NODES[@]}"; do
      NODE_HOSTNAME=$(echo "$NODE" | cut -d'.' -f1)
      NODE_CONFIG_FILE="$RENDERED_DIR/talos/worker-${NODE_HOSTNAME}.yaml"
      
      log_info "  Creating config for worker node $NODE -> $NODE_CONFIG_FILE"
      
      # Copy base worker.yaml to node-specific file
      cp "$OVERLAY_DIR/talos/worker.yaml" "$NODE_CONFIG_FILE"
      
      # Detect and append disk configs for this specific node
      log_info "  Detecting disks on node $NODE..."
      DISK_CONFIGS=$(detect_node_disks "$NODE" "'$TALOSCONFIG'")
      
      if [ -n "$DISK_CONFIGS" ]; then
        log_info "  Additional disks detected on worker node $NODE, generating disk configs..."
        generate_node_disk_configs "$NODE" "$NODE_CONFIG_FILE" "$TALOS_DISK_ENCRYPTION_KMS_URL" "$TALOSCONFIG"
      else
        log_info "    No additional disks found on $NODE (only system disk detected)"
      fi
    done
    
    # Apply worker configuration
    log_info "Applying Talos config to worker nodes..."
    for NODE in "${TALOS_WORKER_NODES[@]}"; do
      NODE_HOSTNAME=$(echo "$NODE" | cut -d'.' -f1)
      NODE_CONFIG_FILE="$RENDERED_DIR/talos/worker-${NODE_HOSTNAME}.yaml"
      
      log_info "  Applying config to worker node $NODE from $NODE_CONFIG_FILE..."
      INSECURE=""
      if ! talosctl get members --nodes "$NODE" &>/dev/null; then
        INSECURE=" --insecure"
      fi
      talosctl apply-config${INSECURE} --nodes "$NODE" --file "$NODE_CONFIG_FILE"
    done
    
    log_success "Worker nodes deployed successfully."
  else
    log_error "Cilium failed to become ready within timeout. Worker nodes will not be deployed."
    DEPLOY_STATUS=6
  fi
else
  log_warn "WARNING: No worker nodes configured in TALOS_WORKER_NODES array."
  log_warn "         Storage classes with -wn suffix will not be able to provision volumes."
  log_warn "         Consider adding worker nodes to enable worker-specific storage."
fi


# ============================================================================
# CSR APPROVAL WATCHER AND DEPLOYMENT
# ============================================================================

log_info "Starting CSR approval for worker nodes..."
# Approve node CSRs for all expected nodes (max_timeout: 300s, inter_node_timeout: 120s)
approve_node_csrs 300 120 "${TALOS_WORKER_NODES[@]}"

# ============================================================================
# CLEANUP
# ============================================================================

# #kill $CSR_WATCHER_PID 2>/dev/null || true
# # Wait for CSR watcher to finish (or timeout)
# wait $CSR_WATCHER_PID 2>/dev/null || true

exit $DEPLOY_STATUS