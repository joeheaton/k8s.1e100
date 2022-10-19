locals {
  vars   = yamldecode(file("../cluster.yaml"))
  suffix = random_id.suffix.hex
}

resource "random_id" "suffix" {
  byte_length = 2
}

module "project" {
  source          = "./fabric/modules/project"
  billing_account = local.vars.billing_account_id
  name            = local.vars.project
  parent          = local.vars.parent_id
  services = [
    "anthosconfigmanagement.googleapis.com",
    "container.googleapis.com",
    "gkeconnect.googleapis.com",
    "gkehub.googleapis.com",
    "multiclusteringress.googleapis.com",
    "multiclusterservicediscovery.googleapis.com",
    "mesh.googleapis.com"
  ]
}

module "vpc" {
  source     = "./fabric/modules/net-vpc"
  project_id = local.vars.project
  name       = "${local.vars.name}-vpc-${local.suffix}"
  subnets = [
    {
      ip_cidr_range = local.vars.subnets.ip_cidr_range
      name          = "gke"
      region        = local.vars.region
      secondary_ip_range = local.vars.subnets.secondary_ip_range
    }
  ]
}

module "cluster" {
  source      = "./fabric/modules/gke-cluster"
  project_id  = local.vars.project
  name        = "${local.vars.name}-${local.suffix}"
  location    = local.vars.region

  vpc_config  = {
    network                   = module.vpc.self_link
    subnetwork                = module.vpc.subnet_self_links["${local.vars.region}/gke"]
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
    master_authorized_ranges = {
      internal-vms = "10.0.0.0/8"
    }
  }

  private_cluster_config = {
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "192.168.0.0/28"
    master_global_access    = false
  }

  # max_pods_per_node = 110
  # min_master_version = null  # defaults to latest official release
  release_channel = "REGULAR"

  # Cannot contain the cluster's zone
  # node_locations = []

  # Conflicts with autopilot  
  cluster_autoscaling = try(local.vars.autopilot, null) != null ? null : {
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
      cloudrun = false
      config_connector = false
      dns_cache = false
      gce_persistent_disk_csi_driver = false
      gcp_filestore_csi_driver = false
      gke_backup_agent = false
      horizontal_pod_autoscaling = false
      http_load_balancing = false
      # istio = {
      #   enable_tls = false
      # }
      kalm = false
      network_policy = false
    },
    try(local.vars.autopilot, null) != null ? {
      gce_persistent_disk_csi_driver = true
      gcp_filestore_csi_driver = false
      horizontal_pod_autoscaling = true
      http_load_balancing = true
    } : {}
  )

  enable_features = {
    autopilot         = local.vars.autopilot
    dataplane_v2      = true
    workload_identity = try(local.vars.autopilot, null) != null ? false : true  # Incompatible with autopilot
  }

  # Autopilot requires both SYSTEM_COMPONENTS and WORKLOADS
  logging_config = distinct(concat(
    try(local.vars.autopilot, null) != null ? [ "SYSTEM_COMPONENTS", "WORKLOADS" ] : [],
    [ "SYSTEM_COMPONENTS", "WORKLOADS" ]
  ))
  
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
    environment = "dev"
  }
}

# Autopilot does not support mutating nodepools
module "nodepool-1" {
  count        = try(local.vars.autopilot, null) != null ? 0 : 1
  source       = "./fabric/modules/gke-nodepool"
  project_id   = local.vars.project
  cluster_name = module.cluster.name
  location     = local.vars.region
  name         = "nodepool-1"

  initial_node_count = 1
  autoscaling_config = {
    min_node_count = 1
    max_node_count = 3
  }

  # kubelet_config = {
  #   cpu_cfs_quota        = ""
  #   cpu_cfs_quota_period = ""
  #   cpu_manager_policy   = ""
  # }

  node_disk_size              = 100
  node_disk_type              = "pd-standard"  
  node_guest_accelerator      = {}
  node_local_ssd_count        = 0
  node_machine_type           = "n1-standard-1"
  node_preemptible            = true
  node_service_account_create = true
  node_service_account_scopes = []
  node_spot                   = true
  node_tags                   = null
  node_taints                 = []
}

module "hub" {
  count        = try(local.vars.hub, null) != null ? 0 : 1
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
        git = {
          gcp_service_account_email = null
          https_proxy               = null
          policy_dir                = "configsync"
          secret_type               = "none"
          source_format             = "hierarchy"
          sync_branch               = "main"
          sync_repo                 = "https://github.com/joeheaton/k8s.1e100"
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
    "default" = [ "cluster-1" ]
  }
}
