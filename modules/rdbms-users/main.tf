

variable "instance" {}
variable "project" {}
variable "user" {}
variable "secret_name" {}
variable "service_account" {}


resource "random_password" "password" {
  length  = 20
  special = false
}


resource "google_sql_user" "user" {
	project		= var.instance.project
	name			= var.user
	instance 	= var.instance.name
  password  = random_password.password.result
}


data "google_iam_policy" "default" {
  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = [
      "serviceAccount:${var.service_account.email}"
    ]
  }
}


resource "google_secret_manager_secret" "password" {
  project   = var.project
  secret_id = var.secret_name

  replication {
    automatic = true
  }
}


resource "google_secret_manager_secret_iam_policy" "password" {
  project     = google_secret_manager_secret.password.project
  secret_id   = google_secret_manager_secret.password.secret_id
  policy_data = data.google_iam_policy.default.policy_data
}


resource "google_secret_manager_secret_version" "password" {
  secret = google_secret_manager_secret.password.id
  secret_data = random_password.password.result
}


output "env" {
  description="Environment variables defined by this module."
  value = {
    DB_USERNAME={
      kind="variable"
      value=google_sql_user.user.name
    }
    DB_PASSWORD={
      kind="secret"
      value=google_secret_manager_secret.password.secret_id
    }
  }
}
