variable "keyring" {}
variable "location" {}
variable "name" {}
variable "project" {}
variable "service_account" {}


data "google_kms_key_ring" "keyring" {
  project   = var.project
  name      = var.keyring
  location  = var.location
}


data "google_kms_crypto_key" "key" {
  key_ring  = data.google_kms_key_ring.keyring.id
  name      = var.name
}


resource "google_kms_crypto_key_iam_member" "crypto_key" {
  crypto_key_id = data.google_kms_crypto_key.key.id
  role          = "roles/cloudkms.signer"
  member        = "serviceAccount:${var.service_account}"
}
