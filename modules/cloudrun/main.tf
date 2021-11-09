

variable "args" {}
variable "connector" {}
variable "environ" {}
variable "image" {}
variable "location" {}
variable "min_replicas" {}
variable "max_replicas" {}
variable "name" {}
variable "ports" {}
variable "project" {}
variable "service_account" {}
variable "variants" {}
variable "vpc_connector" {}


locals {
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

      containers {
        image = each.value.image
        args = each.value.args

        dynamic "ports" {
          for_each = each.value.ports
          content {
            name            = ports.value.name
            container_port  = ports.value.port
          }
        }

        env {
          name  = "HTTP_ALLOWED_HOSTS"
          value = "*"
        }

        dynamic "env" {
          for_each = {
            for name, spec in each.value.environ:
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


output "environ" {
  value = var.environ
}
