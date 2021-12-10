variable "args" {}
variable "connector" {}
variable "deployers" {}
variable "enable_cdn" {}
variable "environ" {}
variable "image" {}
variable "ingress" {}
variable "invokers" {}
variable "kind" {}
variable "location" {}
variable "min_replicas" {}
variable "max_replicas" {}
variable "name" {}
variable "ports" {}
variable "project" {}
variable "service_account" {}
variable "topics" {}
variable "volumes" {}
variable "vpc_connector" {}


locals {
  environ=merge({
    HTTP_ALLOWED_HOSTS: {
      kind="variable"
      value="*"
    }
  }, var.environ)
}


data "google_iam_policy" "default" {
  binding {
    role    = "roles/run.invoker"
    members = toset(concat(var.invokers, [
			"serviceAccount:${var.service_account.email}"
		]))
  }

  binding {
    role    = "roles/run.developer"
    members = var.deployers
  }
}


resource "google_cloud_run_service_iam_policy" "default" {
  location    = google_cloud_run_service.service.location
  project     = google_cloud_run_service.service.project
  service     = google_cloud_run_service.service.name
  policy_data = data.google_iam_policy.default.policy_data
}


resource "google_cloud_run_service" "service" {
  provider    = google-beta
  project     = var.project
  name        = var.name
  location    = var.location

  metadata {
    annotations = {
      "run.googleapis.com/ingress": var.ingress
    }
  }

  autogenerate_revision_name = true

  template {

    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = var.vpc_connector.id
        "run.googleapis.com/vpc-access-egress"    = "private-ranges-only"
        "autoscaling.knative.dev/minScale"        = var.min_replicas
        "autoscaling.knative.dev/maxScale"        = var.max_replicas
      }
    }

    spec {
      container_concurrency = 100
      service_account_name  = var.service_account.email

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
        image = var.image
        args = var.args

        dynamic "volume_mounts" {
          for_each = var.volumes
          content {
            name        = volume_mounts.value.secret.name
            mount_path  = volume_mounts.value.mount
          }
        }

        dynamic "ports" {
          for_each = var.ports
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

  lifecycle {
    ignore_changes = [
      template.0.spec.0.containers.0.image
    ]
  }

}

resource "random_id" "triggers" {
  for_each    = var.topics
  byte_length = 4
}


resource "google_eventarc_trigger" "triggers" {
  depends_on      = [random_id.triggers]
  for_each        = var.topics
  project         = var.project
  name            = "${var.name}-${random_id.triggers[each.key].hex}"
  location        = var.location
  service_account = var.service_account.email

  destination {
    cloud_run_service {
      service = google_cloud_run_service.service.name
      region  = var.location
    }
  }

  transport {
    pubsub {
      topic = each.value.name
    }
  }

  matching_criteria {
    attribute = "type"
    value = "google.cloud.pubsub.topic.v1.messagePublished"
  }
}
