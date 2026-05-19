resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "alchemyst-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Public subnet (gateway VM lives here)
resource "google_compute_subnetwork" "public" {
  project                  = var.project_id
  name                     = "public-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.self_link
  ip_cidr_range            = "10.10.1.0/24"
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private subnet (inference VM lives here — no public IP)
resource "google_compute_subnetwork" "private" {
  project                  = var.project_id
  name                     = "private-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.self_link
  ip_cidr_range            = "10.10.2.0/24"
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router + NAT (private subnet gets internet egress for pip install)
resource "google_compute_router" "router" {
  project = var.project_id
  name    = "alchemyst-router"
  region  = var.region
  network = google_compute_network.vpc.self_link
}

resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "alchemyst-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall rules (deny-by-default; only what's explicitly needed)

# SSH via IAP — gateway and inference VMs
resource "google_compute_firewall" "allow_iap_ssh" {
  project  = var.project_id
  name     = "allow-iap-ssh"
  network  = google_compute_network.vpc.name
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google IAP CIDR only — not the open internet
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]
}

# iii engine WebSocket — inference VM → gateway VM (internal only)
resource "google_compute_firewall" "allow_engine_internal" {
  project  = var.project_id
  name     = "allow-iii-engine-internal"
  network  = google_compute_network.vpc.name
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["49134"]
  }

  source_ranges = ["10.10.2.0/24"] # private subnet only
  target_tags   = ["iii-engine"]
}

# HTTP/S from GCP LB health-check CIDRs
resource "google_compute_firewall" "allow_lb_health_check" {
  project  = var.project_id
  name     = "allow-lb-health-check"
  network  = google_compute_network.vpc.name
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["3111", "80", "443"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["http-server"]
}

# Direct HTTP on port 3111 from internet (used when no LB / domain configured)
resource "google_compute_firewall" "allow_api_direct" {
  project  = var.project_id
  name     = "allow-api-direct"
  network  = google_compute_network.vpc.name
  priority = 1100

  allow {
    protocol = "tcp"
    ports    = ["3111"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

# ICMP within VPC for debugging
resource "google_compute_firewall" "allow_internal_icmp" {
  project  = var.project_id
  name     = "allow-internal-icmp"
  network  = google_compute_network.vpc.name
  priority = 1000

  allow { protocol = "icmp" }

  source_ranges = ["10.10.0.0/16"]
}
