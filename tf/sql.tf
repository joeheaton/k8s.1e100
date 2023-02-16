module "sql" {
  for_each          = local.vars.sql
  source            = "./fabric/modules/cloudsql-instance"
  project_id        = local.vars.project
  network           = module.vpc.network.self_link
  name              = "sql-${each.key}-${local.suffix}"
  region            = local.vars.region
  availability_type = local.vars.sql[each.key].availability_type
  database_version  = local.vars.sql[each.key].version
  databases         = local.vars.sql[each.key].databases
  flags             = local.vars.sql[each.key].flags
  tier              = local.vars.sql[each.key].tier
  users             = local.vars.sql[each.key].users
}
