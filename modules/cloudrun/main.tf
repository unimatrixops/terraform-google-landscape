

variable "args" {}
variable "connector" {}
variable "deployers" {}
variable "enable_cdn" {}
variable "environ" {}
variable "functions" {}
variable "image" {}
variable "location" {}
variable "min_replicas" {}
variable "max_replicas" {}
variable "name" {}
variable "ports" {}
variable "project" {}
variable "service_account" {}
variable "variants" {}
variable "volumes" {}
variable "vpc_connector" {}


locals {
  environ=merge({
    HTTP_ALLOWED_HOSTS: {
      kind="variable"
      value="*"
    }
  }, var.environ)
  variants={
    for variant in var.variants:
    variant.name => merge(
      {
        max_replicas=var.max_replicas
        min_replicas=var.min_replicas
        location=var.location
      },
      variant,
      {environ=merge(var.environ, try(variant.env, {}))},
      {
        args=var.args
        image=var.image
        ports=var.ports
        project=var.project
        service_account=var.service_account
        vpc_connector=var.vpc_connector
      }
    )
  }
}


data "google_iam_policy" "default" {
  binding {
    role    = "roles/run.invoker"
    members = ["allUsers"]
  }

  binding {
    role    = "roles/run.developer"
    members = var.deployers
  }
}


resource "google_cloud_run_service" "service" {
  provider    = google-beta
  project     = var.project
  for_each    = local.variants
  name        = each.value.name
  location    = each.value.location

  metadata {
    annotations = {
      "run.googleapis.com/ingress": "internal-and-cloud-load-balancing"
    }
  }

  autogenerate_revision_name = true

  template {

    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = each.value.vpc_connector.id
        "run.googleapis.com/vpc-access-egress"    = "private-ranges-only"
        "autoscaling.knative.dev/minScale"        = each.value.min_replicas
        "autoscaling.knative.dev/maxScale"        = each.value.max_replicas
      }
    }

    spec {
      container_concurrency = 100
      service_account_name  = each.value.service_account.email

      dynamic "volumes" {
        for_each = var.volumes
        content {
          name = volumes.value.secret.name

          secret {
            secret_name = volumes.value.secret.name

            items {
              key = "latest"
              path = volumes.value.path
            }
          }
        }
      }

      containers {
        image = each.value.image
        args = each.value.args

        dynamic "volume_mounts" {
          for_each = var.volumes
          content {
            name        = volume_mounts.value.secret.name
            mount_path  = volume_mounts.value.mount
          }
        }

        dynamic "ports" {
          for_each = each.value.ports
          content {
            name            = ports.value.name
            container_port  = ports.value.port
          }
        }

        dynamic "env" {
          for_each = {
            for name, spec in local.environ:
            name => spec if spec.kind == "variable"
          }
          content {
            name  = env.key
            value = env.value.value
          }
        }

        dynamic "env" {
          for_each = {
            for name, spec in each.value.environ:
            name => spec if spec.kind == "secret"
          }
          content {
            name  = env.key
            value_from {
              secret_key_ref {
                name = env.value.value
                key = "latest"
              }
            }
          }
        }

      }
    }
  }

  lifecycle {
    ignore_changes = [
			template.0.spec.0.containers.0.image
    ]
  }

}

resource "google_compute_region_network_endpoint_group" "endpoints" {
  for_each              = local.variants
  project               = var.project
  network_endpoint_type = "SERVERLESS"
  region                = each.value.location
  name                  = each.value.name

  cloud_run {
    service = google_cloud_run_service.service[each.key].name
  }
}


resource "google_compute_backend_service" "default" {
  project     = var.project
  name        = var.name
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30
  enable_cdn  = var.enable_cdn

  dynamic "cdn_policy" {
    for_each = (var.enable_cdn) ? [null] : []
    content {
      cache_mode                    = "USE_ORIGIN_HEADERS"
      signed_url_cache_max_age_sec  = 7200
    }
  }

  dynamic "backend" {
    for_each = local.variants
    content {
      group = google_compute_region_network_endpoint_group.endpoints[backend.key].self_link
    }
  }
}


resource "google_cloud_run_service_iam_policy" "default" {
  for_each    = local.variants
  location    = google_cloud_run_service.service[each.key].location
  project     = google_cloud_run_service.service[each.key].project
  service     = google_cloud_run_service.service[each.key].name
  policy_data = data.google_iam_policy.default.policy_data
}


# Service-scoped Cloud Run functions.
data "google_storage_bucket" "bucket" {
  name = "unimatrix-public"
}

data "google_storage_bucket_object" "archive" {
  name    = "seed/python-google-cloudrun.zip"
  bucket  = data.google_storage_bucket.bucket.name
}


resource "google_cloudfunctions_function" "functions" {
  for_each              = var.functions
  project               = var.project
  name                  = each.value.qualname
  description           = each.value.description
  entry_point           = each.value.entry_point
  runtime               = each.value.runtime
  region                = each.value.region
  timeout               = each.value.timeout
  trigger_http          = (each.value.trigger == "http") ? true : false
  service_account_email = var.service_account.email
  source_archive_bucket = data.google_storage_bucket.bucket.name
  source_archive_object = data.google_storage_bucket_object.archive.name
  environment_variables = {
    for key, spec in local.environ:
    key => spec.value if spec.kind == "variable"
  }
}


output "environ" {
  value = var.environ
}
