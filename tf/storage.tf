module "state_bucket" {
  source        = "./fabric/modules/gcs"
  project_id    = local.vars.project
  prefix        = "gcs-state"
  name          = "${local.vars.name}-${local.suffix}"
  location      = "EU"
  force_destroy = false
}

output "state_bucket" {
  description = "Terraform State Bucket"
  value       = module.state_bucket.name
}
