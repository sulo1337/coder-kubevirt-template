terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25.2"
    }
  }
}

variable "namespace" {
  description = <<-EOF
  Kubernetes namespace to deploy the workspace VM into

  EOF
  default     = "coder"
}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

provider "coder" {
}

provider "kubernetes" {
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {

}

data "coder_parameter" "os_image" {
    name = "os_image"
    display_name = "OS Image"
    description = "OS Image type should your workspace use?"
    default = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-disk-kvm.img"
    mutable = false
    option {
        name = "Ubuntu 22.04"
        value = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-disk-kvm.img"
        icon = "/icon/ubuntu.svg"
    }
    option {
        name = "Fedora 39"
        value = "https://download.fedoraproject.org/pub/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2"
        icon = "/icon/fedora.svg"
    }
    option {
        name = "Debian 12"
        value = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
        icon = "/icon/debian.svg"
    }
    option {
        name = "Arch Linux"
        value = "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
        icon = "https://cdn0.iconfinder.com/data/icons/flat-round-system/512/archlinux-512.png"
    }
    option {
        name = "AlmaLinux 9"
        value = "https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
        icon = "/icon/almalinux.svg"
    }
    option {
        name = "CentOS Stream 9"
        value = "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
        icon = "/icon/centos.svg"
    }
    option {
        name = "Rocky Linux 9"
        value = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
        icon = "/icon/rockylinux.svg"
    }
}

data "coder_parameter" "linux_user" {
  name        = "Linux username"
  type        = "string"
  description = "Username for default coder workspace linux user"
  validation {
    regex = "^[a-z_][a-z0-9_-]{0,31}$"
    error = "Username must satisfy regex /^[a-z_][a-z0-9_-]{0,31}$/"
  }
  default = "coder"
}

data "coder_parameter" "cpu" {
  name        = "CPU cores"
  type        = "number"
  description = "Number of CPU Cores"
  icon        = "https://png.pngtree.com/png-clipart/20191122/original/pngtree-processor-icon-png-image_5165793.jpg"
  validation {
    min = 1
    max = 4
  }
  mutable = true
  default = 2
  order   = 1
}

data "coder_parameter" "memory" {
  name        = "Memory (__ MB)"
  type        = "number"
  description = ""
  icon        = "https://www.vhv.rs/dpng/d/33-338595_random-access-memory-logo-hd-png-download.png"
  validation {
    min = 1024
    max = 8192
  }
  mutable = true
  default = 4096
  order   = 2
}

data "coder_parameter" "disk_size" {
  name        = "PVC (your rootfs) storage size"
  type        = "number"
  description = "Number of GB of storage"
  icon        = "https://www.pngall.com/wp-content/uploads/5/Database-Storage-PNG-Clipart.png"
  validation {
    min       = 4
    max       = 64
    monotonic = "increasing"
  }
  mutable = false
  default = 16
  order   = 3
}

resource "coder_agent" "dev" {
  count = data.coder_workspace.me.start_count
  arch                   = "amd64"
  auth                   = "token"
  dir                    = "/home/${data.coder_parameter.linux_user.value}"
  os                     = "linux"
  startup_script_timeout = 300
  startup_script         = <<EOT
    set -e

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.11.0
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat cpu"
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat mem"
  }
  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = "coder stat disk --path /"
  }
  display_apps {
    vscode          = true
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = true
    port_forwarding_helper = true
  }
}

resource "coder_app" "code-server" {
  agent_id     = try(coder_agent.dev[0].id, "")
  slug         = "code-server-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
  display_name = "code-server"
  icon         = "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9a/Visual_Studio_Code_1.35_icon.svg/2560px-Visual_Studio_Code_1.35_icon.svg.png"
  url          = "http://localhost:13337/?folder=/home/${data.coder_parameter.linux_user.value}"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

# cloud init user data and coder agent api token is stored in secret
# secret is destroyed on stopping workspace and re-created on starting a workspace
resource "kubernetes_secret" "cloudinit-secret" {
  count = data.coder_workspace.me.transition == "start" ? 1 : 0
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-cloudinit"
    namespace = var.namespace
  }
  data = {
    userdata = templatefile("cloud-config.yaml.tftpl", {
      hostname = lower(data.coder_workspace.me.name)
      username = lower(data.coder_parameter.linux_user.value)
      init_script = base64encode(try(coder_agent.dev[0].init_script, ""))
      coder_agent_token = try(coder_agent.dev[0].token, "")
    })
  }
}

resource "kubernetes_manifest" "virtualmachine" {
  count = data.coder_workspace.me.transition == "start" ? 1 : 0
  manifest = {
    "apiVersion" = "kubevirt.io/v1"
    "kind"       = "VirtualMachine"
    "metadata" = {
      "labels" = {
        "kubevirt.io/vm" = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
      }
      "name"      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
      "namespace" = "${var.namespace}"
    }
    "spec" = {
      "running" = true
      "template" = {
        "metadata" = {
          "creationTimestamp" = null
          "labels" = {
            "kubevirt.io/vm" = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
          }
        }
        "spec" = {
          "domain" = {
            "devices" = {
              "disks" = [
                {
                  "disk" = {
                    "bus" = "virtio"
                  }
                  "name" = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-rootfs"
                },
                {
                  "disk" = {
                    "bus" = "virtio"
                  }
                  "name" = "cloudinitdisk"
                }
              ]
              "interfaces" = [
                {
                  "masquerade" = {}
                  "name"       = "default"
                },
              ]
            }
            "resources" = {
              "requests" = {
                "cpu"    = "${data.coder_parameter.cpu.value}"
                "memory" = "${data.coder_parameter.memory.value}M"
              }
            }
          }
          "networks" = [
            {
              "name" = "default"
              "pod"  = {}
            },
          ]
          "terminationGracePeriodSeconds" = 300
          "volumes" = [
            {
              "dataVolume" = {
                "name" = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-rootfs"
              }
              "name" = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-rootfs"
            },
            {
              "cloudInitNoCloud" = {
                "networkData" = <<-EOT
                #cloud-config
                network:
                  version: 2
                  ethernets:
                    enp1s0:
                      dhcp4: true
                EOT
                "secretRef" = {
                  name = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-cloudinit"
                }
              }
              "name" = "cloudinitdisk"
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "datavolume" {
  manifest = {
    "apiVersion" = "cdi.kubevirt.io/v1beta1"
    "kind"       = "DataVolume"
    "metadata" = {
      "name"      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-rootfs"
      "namespace" = "${var.namespace}"
    }
    "spec" = {
      "pvc" = {
        "accessModes" = [
          "ReadWriteOnce",
        ]
        "resources" = {
          "requests" = {
            "storage" = "${data.coder_parameter.disk_size.value}G"
          }
        }
      }
      "source" = {
        "http" = {
          "url" = "${data.coder_parameter.os_image.value}"
        }
      }
    }
  }
}

