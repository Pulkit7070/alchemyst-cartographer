variable "project_id" {
  type = string
}

variable "alert_notification_email" {
  type    = string
  default = ""
}

variable "gateway_public_ip" {
  type        = string
  description = "Public IP of the gateway VM - used for uptime check"
  default     = ""
}

