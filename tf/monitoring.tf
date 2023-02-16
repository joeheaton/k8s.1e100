# Ops Agent on all VMs
module "ops_agent_policy" {
  count   = local.vars.gke.ops_agent == true ? 1 : 0
  source  = "terraform-google-modules/cloud-operations/google//modules/agent-policy"
  version = "~> 0.2.3"

  project_id = local.vars.project
  policy_id  = "ops-agents-${local.vars.name}"
  agent_rules = [
    {
      type               = "ops-agent"
      version            = "current-major"
      package_state      = "installed"
      enable_autoupgrade = true
    },
  ]
  os_types = [
    {
      short_name = "centos"
    },
    {
      short_name = "debian"
    },
    {
      short_name = "rhel"
    },
    {
      short_name = "sles"
    },
    {
      short_name = "ubuntu"
    }
  ]
  group_labels = [
    {
      deployment = local.vars.name
    }
  ]
}
