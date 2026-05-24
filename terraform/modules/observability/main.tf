locals {
  notification_channels = var.alert_notification_email != "" ? [
    google_monitoring_notification_channel.email[0].name
  ] : []
}

# Notification channel (email)
resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_notification_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "Email Alerts"
  type         = "email"
  labels = {
    email_address = var.alert_notification_email
  }
}

# Uptime check on the API endpoint
resource "google_monitoring_uptime_check_config" "api" {
  project      = var.project_id
  display_name = "API /healthz"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/healthz"
    port         = 3111
    use_ssl      = false
    validate_ssl = false
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.gateway_public_ip != "" ? var.gateway_public_ip : "0.0.0.0"
    }
  }
}

# Alert: API uptime failure
resource "google_monitoring_alert_policy" "api_down" {
  project      = var.project_id
  display_name = "API Endpoint Down"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failed"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  notification_channels = local.notification_channels
  severity              = "CRITICAL"
}

# Alert: Gateway VM CPU > 80% for 5 min
resource "google_monitoring_alert_policy" "gateway_cpu" {
  project      = var.project_id
  display_name = "Gateway VM High CPU"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization > 80%"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\" metadata.system_labels.name=\"gateway-vm\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
  severity              = "WARNING"
}

# Alert: Inference VM CPU > 90% for 10 min
resource "google_monitoring_alert_policy" "inference_cpu" {
  project      = var.project_id
  display_name = "Inference VM High CPU"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization > 90%"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\" metadata.system_labels.name=\"inference-vm\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.9
      duration        = "600s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.notification_channels
  severity              = "WARNING"
}

# Dashboard (JSON as heredoc - terraform fmt does not touch heredoc contents)
resource "google_monitoring_dashboard" "main" {
  project        = var.project_id
  dashboard_json = <<-EOT
    {
      "displayName": "Alchemyst Inference Dashboard",
      "gridLayout": {
        "columns": "2",
        "widgets": [
          {
            "title": "Gateway CPU",
            "xyChart": {
              "dataSets": [{
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\" metadata.system_labels.\"name\"=\"gateway-vm\"",
                    "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
                  }
                }
              }]
            }
          },
          {
            "title": "Inference CPU",
            "xyChart": {
              "dataSets": [{
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\" metadata.system_labels.\"name\"=\"inference-vm\"",
                    "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
                  }
                }
              }]
            }
          },
          {
            "title": "Gateway Network Egress (bytes/s)",
            "xyChart": {
              "dataSets": [{
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/network/sent_bytes_count\" resource.type=\"gce_instance\" metadata.system_labels.\"name\"=\"gateway-vm\"",
                    "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE" }
                  }
                }
              }]
            }
          },
          {
            "title": "Inference Memory Used",
            "xyChart": {
              "dataSets": [{
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/memory/balloon/ram_used\" resource.type=\"gce_instance\" metadata.system_labels.\"name\"=\"inference-vm\"",
                    "aggregation": { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
                  }
                }
              }]
            }
          }
        ]
      }
    }
  EOT
}
