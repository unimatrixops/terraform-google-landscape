variable "description" {}
variable "environ" {}
variable "name" {}
variable "project" {}
variable "region" {}
variable "runtime" {}
variable "timeout" {}
variable "trigger" {}


resource "google_cloudfunctions_function" "function" {
  name          = var.name
  description   = var.description
  runtime       = var.runtime
  region        = var.region
  timeout       = var.timeout
  trigger_http  = (var.trigger == "http") ? true : false
}
