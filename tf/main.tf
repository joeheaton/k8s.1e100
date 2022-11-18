locals {
  vars   = yamldecode(file("../cluster.yaml"))
  suffix = random_id.suffix.hex
}

output "suffix" {
  value       = local.suffix
  description = "Unique resource suffix."
}

resource "random_id" "suffix" {
  byte_length = 2
}

module "project" {
  source          = "./fabric/modules/project"
  billing_account = local.vars.billing_account_id
  name            = local.vars.project
  parent          = local.vars.parent_id
  project_create  = local.vars.project_create
  services = distinct(concat(
    local.vars.k8s.bastion == true ? [
      "compute.googleapis.com",
      "iap.googleapis.com",
      "oslogin.googleapis.com",
      "storage-api.googleapis.com"
    ] : [],
    [
      "anthosconfigmanagement.googleapis.com",
      "container.googleapis.com",
      # TODO: Enable auditing when https://github.com/hashicorp/terraform-provider-google/issues/12778
      # For now: Enable in https://console.cloud.google.com/kubernetes/security/dashboard
      "containersecurity.googleapis.com",
      "gkeconnect.googleapis.com",
      "gkehub.googleapis.com",
      "monitoring.googleapis.com",
      "multiclusteringress.googleapis.com",
      "multiclusterservicediscovery.googleapis.com",
      "mesh.googleapis.com"
    ]
  ))
}

module "vpc" {
  source     = "./fabric/modules/net-vpc"
  project_id = local.vars.project
  name       = "${local.vars.name}-vpc-${local.suffix}"
  subnets = [
    {
      ip_cidr_range      = local.vars.k8s.subnets.ip_cidr_range
      name               = "gke"
      region             = local.vars.region
      secondary_ip_ranges = local.vars.k8s.subnets.secondary_ip_ranges
    }
  ]
}

module "firewall" {
  count         = local.vars.firewall == {} ? 0 : 1
  source        = "./fabric/modules/net-vpc-firewall"
  project_id    = local.vars.project
  network       = module.vpc.name
  egress_rules  = local.vars.firewall == {} ? null : local.vars.firewall.egress
  ingress_rules = local.vars.firewall == {} ? null : local.vars.firewall.ingress
}

module "nat" {
  source         = "./fabric/modules/net-cloudnat"
  project_id     = local.vars.project
  region         = local.vars.region
  name           = "${local.vars.name}-nat-${local.suffix}"
  router_network = module.vpc.name
}

module "iap_bastion_sa" {
  count      = local.vars.k8s.bastion == true ? 1 : 0
  source     = "./fabric/modules/iam-service-account"
  project_id = local.vars.project
  name       = "k8s-bastion-sa-${local.suffix}"

  iam_project_roles = {
    "${local.vars.project}" = [
      "roles/compute.osLogin",
      "roles/compute.viewer",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/monitoring.viewer"
    ]
  }
}

module "iap_bastion" {
  count   = local.vars.k8s.bastion == true ? 1 : 0
  source  = "terraform-google-modules/bastion-host/google"
  version = "~>5.0.1"
  project = local.vars.project
  zone    = local.vars.zone
  network = module.vpc.network.self_link
  subnet  = module.vpc.subnet_self_links[keys(module.vpc.subnets)[0]]

  # name        = "k8s-bastion-${local.suffix}"
  # name_prefix = "k8s-bastion-${local.suffix}-tmpl"
  image_family  = "ubuntu-minimal-2204-lts"
  image_project	= "ubuntu-os-cloud"
  machine_type  = "e2-micro"
  preemptible   = true

  service_account_email = module.iap_bastion_sa[0].email

  # members = [
  #   "group:devs@example.com",
  # ]

  labels        = {
    deployment  = local.vars.name
  }

  startup_script = <<-EOF
    apt-get update
    # Install TinyProxy
    apt-get install -y tinyproxy
    sed -ri 's|^(Allow 127\.0\.0\.1$)|\1\nAllow localhost|g' /etc/tinyproxy/tinyproxy.conf
    systemctl restart tinyproxy
    # Allow SSH port forwarding
    echo "AllowTCPForwarding yes" >> /etc/ssh/sshd_config
    echo "GatewayPorts yes" >> /etc/ssh/sshd_config
    systemctl reload sshd
  EOF
}

output "iap_bastion_hostname" {
  value = module.iap_bastion == [] ? null : module.iap_bastion[0].hostname
  description = "IAP Bastion IP hostname"
}

module "cluster" {
  source     = "./fabric/modules/gke-cluster"
  project_id = local.vars.project
  name       = "${local.vars.name}-${local.suffix}"
  location   = local.vars.region

  vpc_config = {
    network    = module.vpc.self_link
    subnetwork = module.vpc.subnet_self_links[keys(module.vpc.subnets)[0]]
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
    master_authorized_ranges = {
      internal-vms = "10.0.0.0/8"
    }
  }

  private_cluster_config = local.vars.gke.private == true ? {
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "192.168.0.0/28"
    master_global_access    = false
  } : {
    enable_private_endpoint = false
    master_global_access    = false
  }

  # max_pods_per_node = 110
  # min_master_version = null  # defaults to latest official release
  release_channel = "REGULAR"

  # Cannot contain the cluster's zone
  # node_locations = []

  # Conflicts with autopilot  
  cluster_autoscaling = local.vars.gke.autopilot == true ? null : {
    cpu_limits = {
      max = 4
      min = 1
    }
    mem_limits = {
      max = 8
      min = 1
    }
  }

  # Required for Autopilot: "gce-persistent-disk-csi-driver", "horizontal-pod-autoscaling", "http-load-balancing"
  enable_addons = merge(
    {
      cloudrun                       = false
      config_connector               = false
      dns_cache                      = false
      gce_persistent_disk_csi_driver = false
      gcp_filestore_csi_driver       = false
      gke_backup_agent               = false
      horizontal_pod_autoscaling     = false
      http_load_balancing            = false
      kalm                           = false
      network_policy                 = false
    },
    try(local.vars.gke.autopilot, null) != null ? {
      gce_persistent_disk_csi_driver = true
      gcp_filestore_csi_driver       = false
      horizontal_pod_autoscaling     = true
      http_load_balancing            = true
    } : {}
  )

  enable_features = {
    autopilot         = local.vars.gke.autopilot
    dataplane_v2      = true
    l4_ilb_subsetting = true
    workload_identity = local.vars.gke.autopilot == true ? false : true # Incompatible with autopilot
  }

  # Autopilot requires both SYSTEM_COMPONENTS and WORKLOADS
  logging_config = distinct(concat(
    local.vars.gke.autopilot == true ? ["SYSTEM_COMPONENTS", "WORKLOADS"] : [],
    ["SYSTEM_COMPONENTS", "WORKLOADS"]
  ))

  monitoring_config = {
    enabled_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus = local.vars.gke.prometheus ? true : false
  }

  maintenance_config = {
    daily_window_start_time = "03:00"

    maintenance_excluisions = []
    # maintenance_exclusions = [ {
    #   end_time = "value"
    #   name = "value"
    #   scope = "value"
    #   start_time = "value"
    # } ]

    recurring_window = null
    # recurring_window = {
    #   end_time = "value"
    #   recurrence = "value"
    #   start_time = "value"
    # }
  }

  labels = {
    deployment  = local.vars.name
  }
}

# Autopilot does not support mutating nodepools
module "nodepool-1" {
  count        = local.vars.gke.autopilot == false ? 1 : 0
  source       = "./fabric/modules/gke-nodepool"
  project_id   = local.vars.project
  cluster_name = module.cluster.name
  location     = local.vars.region
  name         = "nodepool-1"

  node_count = {
    initial = local.vars.k8s.node_count.initial
    current = local.vars.gke.autopilot == true ? null : local.vars.k8s.node_count.current
  }

  node_config = {
    boot_disk_kms_key = null
    disk_size_gb = 100
    disk_type = "pd-standard"
    ephemeral_ssd_count = 0
    gcfs = null
    guest_accelerator = null
    gvnic = local.vars.gke.gvnic
    image_type = null
    kubelet_config = null
    linux_node_config_sysctls = {}
    local_ssd_count = 0
    machine_type = null
    metadata = {}
    min_cpu_platform = null
    preemptible = true
    sandbox_config_gvisor = null
    shielded_instance_config = {
      enable_integrity_monitoring = false
      enable_secure_boot = false
    }
    spot = true
    workload_metadata_config_mode = null
  }
}

module "hub" {
  count      = local.vars.gke.hub == true ? 1 : 0
  source     = "./fabric/modules/gke-hub"
  project_id = module.project.project_id

  clusters = {
    cluster-1 = module.cluster.id
  }

  features = {
    appdevexperience             = false
    configmanagement             = false
    identityservice              = false
    multiclusteringress          = null
    servicemesh                  = false
    multiclusterservicediscovery = false
  }

  workload_identity_clusters = []

  configmanagement_templates = {
    default = {
      binauthz = false
      config_sync = {
        git = local.vars.gke.config_sync ? {
          gcp_service_account_email = null
          https_proxy               = null
          policy_dir                = "configsync"
          secret_type               = "none"
          source_format             = "hierarchy"
          sync_branch               = "main"
          sync_repo                 = "https://github.com/joeheaton/k8s.1e100"
          sync_rev                  = null
          sync_wait_secs            = null
        } : {
          gcp_service_account_email = null
          https_proxy               = null
          policy_dir                = null
          secret_type               = null
          source_format             = null
          sync_branch               = null
          sync_repo                 = null
          sync_rev                  = null
          sync_wait_secs            = null
        }
        prevent_drift = false
        source_format = "hierarchy"
      }
      hierarchy_controller = {
        enable_hierarchical_resource_quota = true
        enable_pod_tree_labels             = true
      }
      policy_controller = {
        audit_interval_seconds     = 120
        exemptable_namespaces      = []
        log_denies_enabled         = true
        referential_rules_enabled  = true
        template_library_installed = true
      }
      version = "v1"
    }
  }

  configmanagement_clusters = {
    "default" = ["cluster-1"]
  }
}
