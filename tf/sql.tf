module "psql" {
  source           = "./fabric/modules/cloudsql-instance"
  project_id       = local.vars.project
  network          = module.vpc.network.self_link
  name             = "psql-${local.vars.name}"
  region           = local.vars.region
  database_version = local.vars.sql.version
  tier             = local.vars.sql.tier
  flags            = local.vars.sql.flags
}
