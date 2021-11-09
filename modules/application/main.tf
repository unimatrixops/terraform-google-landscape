

variable "env" {}
variable "name" {}
variable "project" {}
variable "qualname" {}
variable "service_account" {}


data "google_iam_policy" "default" {
  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = [
      "serviceAccount:${var.service_account.email}"
    ]
  }
}


resource "random_password" "secret-key" {
  length  = 64
}


resource "google_secret_manager_secret" "secret-key" {
  project   = var.project
  secret_id = "${var.qualname}-secret-key"

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


output "env" {
  description="Environment variables defined by this module."
  value = merge(
    var.env,
    {
      SECRET_KEY={
        kind="secret"
        value=google_secret_manager_secret.secret-key.secret_id
      }
    }
  )
}


output "secret_name" {
  value=google_secret_manager_secret.secret-key.secret_id
  description="The name of the secret holding the application secret key."
}
