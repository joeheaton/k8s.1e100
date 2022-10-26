module "sql" {
  for_each          = local.vars.sql
  source            = "./fabric/modules/cloudsql-instance"
  project_id        = local.vars.project
  network           = module.vpc.network.self_link
  name              = "sql-${each.key}-${local.suffix}"
  region            = local.vars.region
  database_version  = local.vars.sql[each.key].version
  tier              = local.vars.sql[each.key].tier
  availability_type = local.vars.sql[each.key].availability_type
  flags             = local.vars.sql[each.key].flags
}
