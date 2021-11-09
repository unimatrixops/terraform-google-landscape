

variable "name" {}
variable "project" {}
variable "secrets" {}
variable "service_accounts" {}


data "google_iam_policy" "default" {
  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = [
      for sa in var.service_accounts:
      "serviceAccount:${sa.email}"
    ]
  }
}


resource "random_password" "secret-key" {
  length  = 64
}


resource "google_secret_manager_secret" "secret-key" {
  project   = var.project
  secret_id = "${var.name}-system-key"

  replication {
    automatic = true
  }
}


resource "google_secret_manager_secret_iam_policy" "secret-key" {
  project     = google_secret_manager_secret.secret-key.project
  secret_id   = google_secret_manager_secret.secret-key.secret_id
  policy_data = data.google_iam_policy.default.policy_data
}


resource "google_secret_manager_secret_version" "secret-key" {
  secret = google_secret_manager_secret.secret-key.id
  secret_data = random_password.secret-key.result
}


resource "google_secret_manager_secret" "secrets" {
  for_each  = var.secrets
  project   = each.value.project
  secret_id = each.value.secret_id

  replication {
    automatic = true
  }
}


resource "google_secret_manager_secret_iam_policy" "secrets" {
  for_each    = var.secrets
  project     = google_secret_manager_secret.secrets[each.key].project
  secret_id   = google_secret_manager_secret.secrets[each.key].secret_id
  policy_data = data.google_iam_policy.default.policy_data
}



output "env" {
  description="Environment variables defined by this module."
  value = merge(
    {
      SYSTEM_KEY={
        kind="secret"
        value=google_secret_manager_secret.secret-key.secret_id
      }
    }
  )
}
