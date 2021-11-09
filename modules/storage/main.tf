

variable "admins" {}
variable "location" {}
variable "name" {}
variable "project" {}
variable "versioned" {}


resource "google_storage_bucket" "private" {
  project       = var.project
  name          = var.name
  location      = var.location
  storage_class = "REGIONAL"
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = var.versioned
  }
}


data "google_iam_policy" "admin" {
  binding {
    role    = "roles/storage.admin"
    members = var.admins
  }
}


resource "google_storage_bucket_iam_policy" "policy" {
  bucket      = google_storage_bucket.private.name
  policy_data = data.google_iam_policy.admin.policy_data
}


output "env" {
  description="Environment variables defined by this module."
  value={
    STORAGE_ENGINE={
      kind="variable"
      value="gcs"
    }
    STORAGE_BUCKET={
      kind="variable"
      value=google_storage_bucket.private.name
    }
  }
}
