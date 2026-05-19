variable "project_id" {
  type        = string
  description = "GCP project ID"

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  type        = string
  description = "Primary GCP region"
  default     = "asia-south1"
}

variable "zone" {
  type        = string
  description = "Primary GCP zone"
  default     = "asia-south1-a"
}

variable "app_version" {
  type        = string
  description = "Git SHA or release tag of the application bundle in GCS"
  default     = "latest"
}

variable "gateway_machine_type" {
  type    = string
  default = "e2-small"

  validation {
    condition     = can(regex("^(e2|n1|n2)-", var.gateway_machine_type))
    error_message = "gateway_machine_type must be an e2, n1, or n2 series instance."
  }
}

variable "inference_machine_type" {
  type    = string
  default = "e2-standard-4"

  validation {
    condition     = can(regex("^(e2|n1|n2)-", var.inference_machine_type))
    error_message = "inference_machine_type must be an e2, n1, or n2 series instance (no GPU instances)."
  }
}

variable "owner_email" {
  type        = string
  description = "Email of the engineer deploying this stack (granted IAP + OS Login access)"

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.owner_email))
    error_message = "owner_email must be a valid email address."
  }
}

variable "alert_notification_email" {
  type        = string
  description = "Email for Cloud Monitoring alerts (leave empty to skip alert channel)"
  default     = ""

  validation {
    condition     = var.alert_notification_email == "" || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.alert_notification_email))
    error_message = "alert_notification_email must be a valid email address or empty string."
  }
}

variable "labels" {
  type = map(string)
  default = {
    env     = "assignment"
    managed = "terraform"
    owner   = "pulkit"
  }
}
