

resource "google_vpc_access_connector" "default" {
  provider      = google-beta
  project       = var.project
  region        = var.region
  network       = var.network
  name          = var.name
  ip_cidr_range = var.cidr
  machine_type  = var.machine_type
}


# Deny ingress traffic from this service.
resource "random_id" "ingress" {
  byte_length = 3
}


resource "google_compute_firewall" "deny-ingress" {
  project     = var.project
  name        = "deny-ingress-vpc-connector-${random_id.ingress.hex}"
  network     = var.network
  direction   = "INGRESS"
  priority    = 999

  source_ranges = [var.cidr]

  deny {
    protocol = "all"
  }
}


# Create firewall egress rules based on the specified
# consumed services.
resource "random_id" "egress" {
  for_each    = var.consumes
  byte_length = 3
}

resource "google_compute_firewall" "egress" {
  for_each    = var.consumes
  project     = var.project
  name        = "allow-egress-${each.value.kind}-${random_id.egress[each.key].hex}"
  network     = var.network
  direction   = "EGRESS"

  target_tags = [format("%s%s",
    "vpc-connector-${google_vpc_access_connector.default.region}-",
    "${google_vpc_access_connector.default.name}"
  )]

  destination_ranges = ["${var.services[each.value.kind][each.value.name].host}/32"]

  allow {
    protocol  = "tcp"
    ports     = [var.services[each.value.kind][each.value.name].port]
  }
}
