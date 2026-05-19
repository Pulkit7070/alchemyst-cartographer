provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ── Required GCP APIs ─────────────────────────────────────────────────────────
locals {
  required_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ── App bundle bucket (VMs pull app from here on startup) ─────────────────────
resource "google_storage_bucket" "app_bundles" {
  project                     = var.project_id
  name                        = "${var.project_id}-app-bundles"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.apis]
}

# ── Network ───────────────────────────────────────────────────────────────────
module "network" {
  source     = "./modules/network"
  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.apis]
}

# ── IAM ───────────────────────────────────────────────────────────────────────
module "iam" {
  source      = "./modules/iam"
  project_id  = var.project_id
  owner_email = var.owner_email

  depends_on = [google_project_service.apis]
}

# ── Compute ───────────────────────────────────────────────────────────────────
module "compute" {
  source                   = "./modules/compute"
  project_id               = var.project_id
  zone                     = var.zone
  region                   = var.region
  public_subnet_self_link  = module.network.public_subnet_self_link
  private_subnet_self_link = module.network.private_subnet_self_link
  gateway_sa_email         = module.iam.gateway_sa_email
  inference_sa_email       = module.iam.inference_sa_email
  gateway_machine_type     = var.gateway_machine_type
  inference_machine_type   = var.inference_machine_type
  app_version              = var.app_version
  labels                   = var.labels

  depends_on = [
    module.network,
    module.iam,
    google_storage_bucket.app_bundles,
  ]
}

# ── Observability ─────────────────────────────────────────────────────────────
module "observability" {
  source                   = "./modules/observability"
  project_id               = var.project_id
  alert_notification_email = var.alert_notification_email
  gateway_public_ip        = module.compute.gateway_public_ip

  depends_on = [module.compute]
}
