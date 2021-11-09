
variable "deployers" {
  type=list(string)
  description="The list of principals that are allowed to used this service account."
}

variable "service_account" {
  type=object({
    project=string
    name=string
  })
}


resource "google_service_account" "default" {
  project     = var.service_account.project
  account_id  = var.service_account.name
}


resource "google_service_account_iam_binding" "deployers" {
  service_account_id  = google_service_account.default.name
  role                = "roles/iam.serviceAccountUser"
  members             = var.deployers
}


output "service_account" {
  value=google_service_account.default
}
