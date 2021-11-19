

variable "project" {}
variable "service_account" {}
variable "service_name" {}


resource "tls_private_key" "actor-key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}


data "google_iam_policy" "default" {
  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = [
      "serviceAccount:${var.service_account}"
    ]
  }
}


resource "google_secret_manager_secret" "actor-key" {
  project   = var.project
  secret_id = "${var.service_name}-actor-key"

  replication {
    automatic = true
  }
}


resource "google_secret_manager_secret_iam_policy" "actor-key" {
  project     = google_secret_manager_secret.actor-key.project
  secret_id   = google_secret_manager_secret.actor-key.secret_id
  policy_data = data.google_iam_policy.default.policy_data
}


resource "google_secret_manager_secret_version" "actor-key" {
  secret = google_secret_manager_secret.actor-key.id
  secret_data = tls_private_key.actor-key.private_key_pem
}


output "volumes" {
  value=[{
    mount="/opt/app/pki/actor"
    path="latest.pem"
    secret={
      name=google_secret_manager_secret.actor-key.secret_id
    }
  }]
}


output "env" {
  value={
    OAUTH2_ACTOR_KEY={
      kind="variable"
      value="/opt/app/pki/actor/latest.pem"
    }
  }
}
