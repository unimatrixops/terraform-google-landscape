

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


output "service_account" {
  value=google_service_account.default
}
