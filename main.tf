#-------------------------------------------------------------------------------
#
#   GOOGLE CLOUD PLATFORM APPLICATION LANDSCAPE
#
#   - Create a VPC connector for use with Cloud Run.
#   - Whitelist services for egress traffic.
#   - Create service accounts for each service.
#   - Create a system secret key.
#
#-------------------------------------------------------------------------------
variable "spec" {}


module "spec" {
  source = "./modules/spec"
  spec   = var.spec
}


module "vpc-connectors" {
  for_each  = module.spec.vpc_connectors
  source    = "./modules/vpc-connector"
  cidr      = each.value.cidr
  consumes  = each.value.consumes
  network   = each.value.network
  name      = each.value.name
  project   = each.value.project
  region    = each.value.region
  services  = module.spec.consumed_services
}


module "iam" {
  depends_on      = [module.spec]
  for_each        = module.spec.service_accounts
  source          = "./modules/iam"
  service_account = each.value
}


module "rdbms" {
  depends_on      = [module.spec, module.iam]
  for_each        = module.spec.databases
  source          = "./modules/rdbms"
  instance        = module.spec.consumed_services[each.value.kind][each.value.host]
  kind            = each.value.kind
  project         = each.value.project
  qualname        = each.value.qualname
}


module "rdbms-users" {
  source          = "./modules/rdbms-users"
  depends_on      = [module.spec, module.rdbms, module.iam]
  for_each        = module.spec.database_users
  project         = module.spec.project
  instance        = module.spec.rdbms[each.value.cluster.host]
  user            = each.value.name
  secret_name     = each.value.secret_name
  service_account = module.iam[each.value.service_name].service_account
}


module "rdbms-env" {
  source      = "./modules/rdbms-env"
  depends_on  = [module.spec, module.iam]

  service         = each.value
  database        = each.value.database.qualname
  instance        = module.spec.rdbms[each.value.database.host]
  service_account = module.iam[each.key].service_account.email

  for_each = {
    for name, spec in module.spec.services:
    name => spec if try(spec.database, "") != ""
  }
}


module "system" {
  source            = "./modules/system"
  depends_on        = [module.spec]
  name              = var.spec.name
  project           = var.spec.project
  secrets           = module.spec.secrets

  service_accounts  = {
    for name, result in module.iam:
    name => result.service_account
  }
}


module "secrets" {
  source        = "./modules/secrets"
  depends_on    = [module.spec, module.iam]
  for_each      = module.spec.services
  project       = module.spec.project
  qualname      = each.value.qualname
  secrets       = each.value.secrets
}


module "application" {
  depends_on          = [module.spec, module.iam]
  for_each            = module.spec.services
  source              = "./modules/application"
  env                 = each.value.env
  name                = each.key
  project             = each.value.project
  qualname            = each.value.qualname
  service_account     = module.iam[each.key].service_account
}


module "cloudrun" {
  source          = "./modules/cloudrun"
  for_each        = module.spec.services
  connector       = each.value.connector
  image           = each.value.image
  location        = each.value.region
  min_replicas    = each.value.min_replicas
  max_replicas    = each.value.max_replicas
  name            = each.value.qualname
  ports           = each.value.ports
  project         = each.value.project
  service_account = module.iam[each.key].service_account
  vpc_connector   = module.vpc-connectors[each.value.connector]

  environ = merge(
    module.system.env,
    module.application[each.key].env,
    module.rdbms-env[each.key].env,
    module.rdbms-users[each.key].env,
    each.value.env,
    each.value.secrets
  )

  depends_on = [
    module.vpc-connectors,
    module.system,
    module.application,
    module.rdbms-env,
    module.rdbms-users,
    module.spec,
    module.iam
  ]
}


output "environ" {
  value = {
    for name, result in module.cloudrun:
    name => result.environ
  }
}
