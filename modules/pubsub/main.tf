variable "name" {}
variable "project" {}
variable "schema" { default=null }


resource "google_pubsub_topic" "topic" {
  project = var.project
  name    = var.name
}
