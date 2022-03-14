

variable "spec" {}


locals {
  admins = toset(try(var.spec.admins, []))

  cache = merge(
    local.consumed_services.redis
  )

  consumed_services={
    redis={
      for k, v in data.google_redis_instance.redis:
      k => merge(v, {
        engine="redis"
      })
    }
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
    for env in local.environments:
    env.name =>  {
      name=env.qualname
      service_name=env.name
      secret_name="${var.spec.name}-${env.name}-db-password"
      cluster=env.database
    } if try(env.database, null) != null
  }

  deployers=try(var.spec.deployers, [])

  environments={
    for x in try(var.spec.environments, []):
    x.name => merge(x, {
      project=var.spec.project
      cache=(try(x.cache, "") == "") ? null : local.cache[x.cache]
      connector="${var.spec.name}-${x.connector}"
      database=(try(x.database, "") != "") ? local.databases[x.database] : null
      deployers=toset(concat(try(x.deployers, []), local.deployers))
      enable_cdn=try(x.enable_cdn, false)
      enable_signing=try(x.enable_signing, false)
      enable_storage=try(x.enable_storage, false)
      image=try(x.image, "gcr.io/cloudrun/hello")
      keys={
        for key in try(x.keys, []):
        "${key.keyring}/${key.name}" => merge({
          project=var.spec.project
        }, key)
      }
      max_replicas=try(x.max_replicas, 100)
      min_replicas=try(x.min_replicas, 0)
      qualname="${var.spec.name}-${x.name}"
      storage_admins=setunion(
        local.admins,
        toset(try(x.storage_admins, []))
      )
      signing_algorithm=try(x.signing_algorithm, "EC")
      storage_name=try(x.storage_name, "private-${var.spec.name}-${x.name}")
      storage_location=try(x.storage_location, var.spec.region)
      storage_versioning=try(x.storage_versioning, false)
      region=try(x.region, var.spec.region)
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
      volumes=try(x.volumes, [])
    })
  }

  keyrings = {
    for x in try(var.spec.keyrings, []):
    x.name => merge({project=var.spec.project}, x)
  }

  listeners = {
    for x in try(var.spec.listeners, []):
    x.name => merge(x, local.environments[x.environment], {
      args=try(x.args, ["runhttp-listener"])
      env={
        for variable in try(x.env, []):
        variable.name => {kind="variable", value=variable.value}
      }
      kind="Listener",
      ingress="internal"
      invokers=concat(
        try(x.invokers, [])
      )
      ports={for port in try(x.ports, [{name="http1", port=8000}]): port.name => port}
      qualname="${var.spec.name}-${x.name}-listener"
      region=try(
        x.region,
        local.environments[x.environment].region,
        var.spec.region
      )
      topics={
        for topic in try(x.topics, []):
        topic.name => merge(x, {
          name="projects/${try(x.project, var.spec.project)}/topics/${var.spec.name}.${topic.name}"
          path=try(topic.path, "/")
          qualname="${var.spec.name}.${x.name}"
        })
      }
    })
  }

  services={
    for x in try(var.spec.services, []):
    x.name => merge(x, local.environments[x.environment], {
      args=try(x.args, ["runhttp"])
      health_check_url=try(x.health_check_url, null)
      keepalive=try(x.keepalive, null)
      ports={for port in try(x.ports, [{name="http1", port=8000}]): port.name => port}
      qualname="${var.spec.name}-${x.name}"
      variants=[
        for variant in try(x.variants, [{name=x.name}]):
        merge(variant, {
          name=format(
            "%s%s",
            "${var.spec.name}-${x.name}",
            (try(x.variants, "") != "") ? "-${variant.name}" : ""
          )
          env={
            for v in try(variant.env, []):
            v.name => {
              kind="variable"
              value=v.value
            }
          }
          volumes=try(x.volumes, [])
        })
      ]
      topics={
        for topic in try(x.topics, []):
        topic.name => merge(x, {
          name="projects/${try(x.project, var.spec.project)}/topics/${var.spec.name}.${topic.name}"
          path=try(topic.path, "/")
          qualname="${var.spec.name}.${x.name}"
          service="${var.spec.name}-${x.name}"
        })
      }
    })
  }

  service_accounts = {
    for x in try(var.spec.environments, []):
    x.name => {
      project=var.spec.project
      name="${var.spec.name}-${x.name}"
      deployers=local.deployers
    }
  }

  topics = {
    for topic in try(var.spec.topics, []):
    "${var.spec.name}.${topic.name}" => merge(topic, {
      name="${var.spec.name}.${topic.name}"
    })
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


output "cache" {
  description="The cache instances used by the deployment."
  value=local.cache
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

output "environments" {
  description="The environment in which Cloud Run instances are deployed."
  value=local.environments
}


output "keyusers" {
  description = "All key users in this deployment."
  value={
    for user in flatten([
      for name, env in local.environments: [
        for k, spec in env.keys:
          merge(spec, {
            qualname="${name}/${k}"
            service_name=name
          })
      ]
    ]): user.qualname => user
  }
}

output "project" {
  value=var.spec.project
}


output "rdbms" {
  description="The database instances used by the deployment."
  value=merge(
    local.consumed_services.postgresql
  )
}


output "secrets" {
  description="Secrets common to all deployment components."
  value={
    for secret in try(var.spec.secrets, []):
    secret.name => {
      project=var.spec.project
      secret_id="${var.spec.name}-${secret.value}"
    }
  }
}


output "listeners" {
  value=local.listeners
  description="The Cloud Run services that are listeners."
}


output "services" {
  value=local.services
  description="The Cloud Run services in this deployment."
}


output "topics" {
  value=local.topics
  description="The Cloud PubSub topics for this deployment."
}


output "service_accounts" {
  value=local.service_accounts
  description="The service accounts created for this deployment."
}
