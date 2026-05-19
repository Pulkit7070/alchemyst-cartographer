locals {
  image = "ubuntu-os-cloud/ubuntu-2204-lts"

  # Startup script shared preamble
  common_init = <<-SH
    #!/usr/bin/env bash
    set -euo pipefail
    apt-get update -y
    apt-get install -y curl wget git unzip jq

    # Create unprivileged service user
    useradd --system --create-home --shell /bin/bash alchemyst || true

    # Pull app bundle from GCS
    mkdir -p /opt/alchemyst
    gsutil cp "gs://${var.project_id}-app-bundles/app-${var.app_version}.tar.gz" \
      /opt/alchemyst/app.tar.gz || \
    gsutil cp "gs://${var.project_id}-app-bundles/app-latest.tar.gz" \
      /opt/alchemyst/app.tar.gz
    tar -xzf /opt/alchemyst/app.tar.gz -C /opt/alchemyst/
    chown -R alchemyst:alchemyst /opt/alchemyst
  SH
}

# Static internal IP for gateway (inference VM needs to know it at boot)
resource "google_compute_address" "gateway_internal" {
  project      = var.project_id
  name         = "gateway-internal-ip"
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = var.public_subnet_self_link
  address      = "10.10.1.10"
}

# Gateway VM
resource "google_compute_instance" "gateway" {
  project      = var.project_id
  name         = "gateway-vm"
  machine_type = var.gateway_machine_type
  zone         = var.zone
  labels       = var.labels

  tags = ["iap-ssh", "iii-engine", "http-server"]

  boot_disk {
    initialize_params {
      image = local.image
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.public_subnet_self_link
    network_ip = google_compute_address.gateway_internal.address
    access_config {} # ephemeral public IP
  }

  service_account {
    email  = var.gateway_sa_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-SH
    ${local.common_init}

    # Install Node.js 20 + bun
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    curl -fsSL https://bun.sh/install | bash
    ln -sf /root/.bun/bin/bun /usr/local/bin/bun

    # Install iii CLI
    npm install -g @iii-org/cli 2>/dev/null || \
    pip3 install iii-cli 2>/dev/null || true

    # Install caller-worker deps
    cd /opt/alchemyst/quickstart/workers/caller-worker
    npm install

    # Patch config.yaml to bind HTTP on 0.0.0.0 (not 127.0.0.1)
    sed -i 's/host: 127.0.0.1/host: 0.0.0.0/' /opt/alchemyst/quickstart/config.yaml

    # Install and start systemd units
    cp /opt/alchemyst/systemd/iii-engine.service      /etc/systemd/system/
    cp /opt/alchemyst/systemd/caller-worker.service   /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now iii-engine
    sleep 3
    systemctl enable --now caller-worker

    echo "gateway startup complete"
  SH

  allow_stopping_for_update = true
}

# Inference VM (no public IP)
resource "google_compute_instance" "inference" {
  project      = var.project_id
  name         = "inference-vm"
  machine_type = var.inference_machine_type
  zone         = var.zone
  labels       = var.labels

  tags = ["iap-ssh"]

  boot_disk {
    initialize_params {
      image = local.image
      size  = 50 # model cache + venv
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.private_subnet_self_link
    # no access_config = no public IP
  }

  service_account {
    email  = var.inference_sa_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
    # Pass gateway internal IP so inference worker can reach the engine
    gateway-internal-ip = google_compute_address.gateway_internal.address
  }

  metadata_startup_script = <<-SH
    ${local.common_init}

    # Install Python 3.11
    apt-get install -y python3.11 python3.11-venv python3-pip

    # Install inference-worker deps in venv
    python3.11 -m venv /opt/alchemyst/venv
    /opt/alchemyst/venv/bin/pip install --upgrade pip
    /opt/alchemyst/venv/bin/pip install \
      -r /opt/alchemyst/quickstart/workers/inference-worker/requirements.txt

    # Fetch gateway IP from instance metadata
    GATEWAY_IP=$(curl -sf -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gateway-internal-ip")

    # Write engine URL into systemd unit override
    mkdir -p /etc/systemd/system/inference-worker.service.d
    cat > /etc/systemd/system/inference-worker.service.d/override.conf <<EOF
    [Service]
    Environment="III_URL=ws://$${GATEWAY_IP}:49134"
    EOF

    cp /opt/alchemyst/systemd/inference-worker.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now inference-worker

    echo "inference startup complete"
  SH

  allow_stopping_for_update = true

  # Inference VM depends on gateway being up (engine must be ready)
  depends_on = [google_compute_instance.gateway]
}
