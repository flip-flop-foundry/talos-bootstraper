# Coder workspace template — Kubernetes Pod + persistent home for the
# talos-bootstrapper dev image.
#
# NOTE ON RENDERING: this file is processed by render-overlay.sh with an
# envsubst *whitelist*, so only ${CODER_*} placeholders defined in the env file
# are substituted. Terraform's own ${...} interpolations (e.g.
# ${data.coder_workspace.me.name}) are NOT in the whitelist and are preserved
# verbatim.

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# Coder runs in-cluster; use the mounted ServiceAccount for the Kubernetes API.
provider "kubernetes" {}

provider "coder" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  namespace     = "${CODER_WORKSPACES_NAMESPACE}"
  workspace_name = lower("coder-${data.coder_workspace_owner.me.username}-${data.coder_workspace.me.name}")
}

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  startup_script = <<-EOT
    set -e
    # The dev image ships the toolchain; just keep the agent alive and land the
    # user in their persistent home directory.
    cd "$HOME"
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "RAM Usage"
    key          = "mem"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
}

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "${local.workspace_name}-home"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "coder"
      "com.coder.workspace.name"     = data.coder_workspace.me.name
      "com.coder.user.username"      = data.coder_workspace_owner.me.username
    }
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "pvckey-2replica-retained-backedup-ssd-cp"
    resources {
      requests = {
        storage = "${CODER_WORKSPACE_STORAGE_SIZE}"
      }
    }
  }
}

resource "kubernetes_pod" "workspace" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = local.workspace_name
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "coder"
      "com.coder.workspace.name"     = data.coder_workspace.me.name
      "com.coder.user.username"      = data.coder_workspace_owner.me.username
    }
  }
  spec {
    # NOTE: We want `hostUsers = false` here for user-namespace isolation, but the
    # hashicorp/kubernetes provider's kubernetes_pod does not yet expose that field.
    # Tracked in coderDeferredWork.md. See:
    #   https://github.com/hashicorp/terraform-provider-kubernetes/issues/2818
    #   https://github.com/hashicorp/terraform-provider-kubernetes/pull/2828
    security_context {
      run_as_non_root = true
      run_as_user     = 1000
      fs_group        = 1000
      seccomp_profile {
        type = "RuntimeDefault"
      }
    }
    automount_service_account_token = false

    container {
      name              = "dev"
      image             = "${CODER_WORKSPACE_IMAGE}"
      image_pull_policy = "IfNotPresent"
      command           = ["sh", "-c", coder_agent.main.init_script]

      security_context {
        run_as_non_root            = true
        run_as_user                = 1000
        allow_privilege_escalation = false
        capabilities {
          drop = ["ALL"]
        }
      }

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      resources {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "4"
          memory = "8Gi"
        }
      }

      volume_mount {
        name       = "home"
        mount_path = "/home/vscode"
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
        read_only  = false
      }
    }
  }
}
