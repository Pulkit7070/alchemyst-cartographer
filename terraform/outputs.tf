output "api_url" {
  description = "Public URL for the inference API"
  value       = "http://${module.compute.gateway_public_ip}:3111"
}

output "gateway_public_ip" {
  value = module.compute.gateway_public_ip
}

output "inference_internal_ip" {
  value = module.compute.inference_internal_ip
}

output "curl_example" {
  description = "Ready-to-run curl command"
  value       = <<-EOT
    curl -X POST http://${module.compute.gateway_public_ip}:3111/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{"messages":[{"role":"user","content":"What is 2+2? Answer in one word."}]}'
  EOT
}

output "ssh_gateway" {
  description = "SSH to gateway VM via IAP"
  value       = "gcloud compute ssh gateway-vm --tunnel-through-iap --zone=${var.zone} --project=${var.project_id}"
}

output "ssh_inference" {
  description = "SSH to inference VM via IAP (private - no public IP)"
  value       = "gcloud compute ssh inference-vm --tunnel-through-iap --zone=${var.zone} --project=${var.project_id}"
}

output "app_bundles_bucket" {
  value = "${var.project_id}-app-bundles"
}
