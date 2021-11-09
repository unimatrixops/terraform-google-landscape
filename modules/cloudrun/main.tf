

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


data "google_iam_policy" "default" {
  binding {
    role    = "roles/run.invoker"
    members = ["allUsers"]
  }
}


resource "google_cloud_run_service" "service" {
  provider    = google-beta
  project     = var.project
  name        = var.name
  location    = var.location

  template {

    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = var.connector
        "run.googleapis.com/vpc-access-egress"    = "private-ranges-only"
        "autoscaling.knative.dev/minScale"        = var.min_replicas
        "autoscaling.knative.dev/maxScale"        = var.max_replicas
      }
    }

    spec {
      container_concurrency = 100
      service_account_name  = var.service_account.email

      containers {
        image = var.image

        dynamic "ports" {
          for_each = var.ports
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
            for name, spec in var.environ:
            name => spec if spec.kind == "variable"
          }
          content {
            name  = env.key
            value = env.value.value
          }
        }

        dynamic "env" {
          for_each = {
            for name, spec in var.environ:
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


resource "google_cloud_run_service_iam_policy" "default" {
  location    = google_cloud_run_service.service.location
  project     = google_cloud_run_service.service.project
  service     = google_cloud_run_service.service.name
  policy_data = data.google_iam_policy.default.policy_data
}


output "environ" {
  value = var.environ
}