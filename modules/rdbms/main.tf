

variable "instance" {}
variable "kind" {}
variable "project" {}
variable "qualname" {}


resource "google_sql_database" "postgresql" {
  count     = (var.kind == "postgresql") ? 1 : 0
  project   = var.project
  instance  = var.instance.name
  name      = var.qualname
  charset   = "UTF8"
  collation = "en_US.UTF8"
}


locals {
  clusters={
    postgresql=google_sql_database.postgresql
  }
}


output "cluster" {
  description="The database cluster that was created."
  value=local.clusters[var.kind]
}
