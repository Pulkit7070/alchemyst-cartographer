# Enable OS Login project-wide
resource "google_compute_project_metadata_item" "os_login" {
  project = var.project_id
  key     = "enable-oslogin"
  value   = "TRUE"
}

# Service account for gateway VM
resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "sa-gateway"
  display_name = "Gateway VM Service Account"
}

resource "google_project_iam_member" "gateway_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}

resource "google_project_iam_member" "gateway_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}

resource "google_project_iam_member" "gateway_storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}

# Service account for inference VM
resource "google_service_account" "inference" {
  project      = var.project_id
  account_id   = "sa-inference"
  display_name = "Inference VM Service Account"
}

resource "google_project_iam_member" "inference_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.inference.email}"
}

resource "google_project_iam_member" "inference_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.inference.email}"
}

resource "google_project_iam_member" "inference_storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.inference.email}"
}

# IAP access for the owner (SSH tunnel through IAP)
resource "google_iap_tunnel_iam_member" "owner" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${var.owner_email}"
}

resource "google_project_iam_member" "owner_oslogin" {
  project = var.project_id
  role    = "roles/compute.osAdminLogin"
  member  = "user:${var.owner_email}"
}
