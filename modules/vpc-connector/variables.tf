

variable "cidr" {
  type=string
}


variable "consumes" {}


variable "name" {
  type=string
}


variable "machine_type" {
  type=string
  default="e2-micro"
}


variable "network" {
  type=string
}


variable "project" {
  type=string
}


variable "region" {
  type=string
}


variable "services" {}
