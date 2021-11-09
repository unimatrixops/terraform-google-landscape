

variable "spec" {}


locals {

  consumed_services={
    redis=data.google_redis_instance.redis
    postgresql={
      for k, v in data.google_sql_database_instance.postgresql:
      k => merge(v, {
        engine="postgresql"
        host=v.private_ip_address
        port=5432
      })
    }
  }

  databases={
    for x in try(var.spec.databases, []):
    x.name => merge(x, {
      project=var.spec.project
      qualname="${var.spec.name}-${x.name}"
    })
  }

  # Maps instances to databases
  database_clusters = {
    for host in toset([for x in try(var.spec.databases, []): x.host]):
       host => toset([
        for cluster in try(var.spec.databases):
        cluster.name if cluster.host == host
      ])
  }

  database_users = {
    for svc in local.services:
    svc.name =>  {
      name=svc.qualname
      service_name=svc.name
      secret_name="${var.spec.name}-${svc.name}-db-password"
      cluster=svc.database
    } if try(svc.database, null) != null
  }

  deployers=try(var.spec.deployers, [])

  services={
    for x in var.spec.services:
    x.name => merge(x, {
      project=var.spec.project
      args=try(x.args, [])
      image=try(x.image, "gcr.io/cloudrun/hello")
      ports={for port in try(x.ports, []): port.name => port}
      connector="${var.spec.name}-${x.connector}"
      region=try(x.region, var.spec.region)
      qualname="${var.spec.name}-${x.name}"
      deployers=toset(concat(try(x.deployers, []), local.deployers))
      min_replicas=try(x.min_replicas, 0)
      max_replicas=try(x.max_replicas, 100)
      database=(try(x.database, "") != "") ? local.databases[x.database] : null
      service_account="${var.spec.name}-${x.name}"
      env=merge(
        {
          for variable in try(var.spec.env, []):
          variable.name => {kind="variable", value=variable.value}
        },
        {
          for variable in try(x.env, []):
          variable.name => {kind="variable", value=variable.value}
        }
      )
      secrets={
        for secret in try(x.secrets, []):
        secret.name => {
          kind="secret",
          value="${var.spec.name}-${secret.secret.name}"
        }
      }
    })
  }

  service_accounts = {
    for x in var.spec.services:
    x.name => {
      project=var.spec.project
      name="${var.spec.name}-${x.name}"
      deployers=local.deployers
    }
  }

  vpc_connectors={
    for x in try(var.spec.vpc_connectors, []):
    "${var.spec.name}-${x.name}" => {
      project=var.spec.project
      name="${var.spec.name}-${x.name}"
      network=var.spec.network
      cidr=x.cidr
      region=var.spec.region
      machine_type=try(x.machine_type, "e2-micro")
      consumes={
        for x in try(x.consumes, []):
        "${x.kind}/${x.name}" => x
      }
    }
  }
}


# Lookup Google services that are specified by `.consumes`. Supported services
# are:
#
# - `postgresql` - Cloud SQL, PostgreSQL
# - `redis` - Memorystore, Redids
data "google_sql_database_instance" "postgresql" {
  for_each  = {for x in var.spec.consumes: x.name => x if x.kind == "postgresql"}
  project   = var.spec.project
  name      = each.value.name
}


data "google_redis_instance" "redis" {
  for_each  = {for x in var.spec.consumes: x.name => x if x.kind == "redis"}
  project   = var.spec.project
  region    = try(each.value.region, var.spec.region)
  name      = each.value.name
}



output "vpc_connectors" {
  value=local.vpc_connectors
}


output "consumed_services" {
  value=local.consumed_services
}


output "databases" {
  description="The database clusters required by this deployment."
  value=local.databases
}


output "database_clusters" {
  description="The list of clusters per instance."
  value=local.database_clusters
}


output "database_users" {
  description="The list of database users per cluster."
  value=local.database_users
}

output "project" {
  value=var.spec.project
}


output "rdbms" {
  description="The database instances used by the deployment."
  value=merge(
    {for k, v in try(local.consumed_services.postgresql, {}): k => v}
  )
}


output "secrets" {
  description="Secrets common to all deployment components."
  value={
    for secret in try(var.spec.secrets):
    secret.name => {
      project=var.spec.project
      secret_id="${var.spec.name}-${secret.value}"
    }
  }
}


output "services" {
  value=local.services
  description="The Cloud Run services in this deployment."
}


output "service_accounts" {
  value=local.service_accounts
  description="The service accounts created for this deployment."
}
