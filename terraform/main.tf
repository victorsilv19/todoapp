locals {
  deployment_name = "${var.instance_name}-${var.environment}"
  common_labels = {
    environment = var.environment
    project     = "pm04-todoapp"
  }
}

data "google_compute_image" "ubuntu" {
  family  = var.ubuntu_version
  project = "ubuntu-os-cloud"
}

resource "google_compute_network" "main" {
  name                    = "${local.deployment_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "app" {
  name                     = "${local.deployment_name}-app-subnet"
  ip_cidr_range            = var.app_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "database" {
  name                     = "${local.deployment_name}-db-subnet"
  ip_cidr_range            = var.database_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

resource "google_compute_firewall" "app_ssh" {
  name      = "${local.deployment_name}-app-ssh"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = var.ssh_allowed_cidrs
  target_tags   = ["todo-app"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "app_http" {
  name      = "${local.deployment_name}-app-http"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["todo-app"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "database_ssh" {
  name      = "${local.deployment_name}-db-ssh"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [var.app_subnet_cidr]
  target_tags   = ["todo-db"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "database_mongodb" {
  name      = "${local.deployment_name}-db-mongodb"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [var.app_subnet_cidr]
  target_tags   = ["todo-db"]

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
}

resource "google_compute_router" "main" {
  name    = "${local.deployment_name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "private_egress" {
  name                               = "${local.deployment_name}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.database.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_instance" "app" {
  name                      = "${local.deployment_name}-app"
  machine_type              = var.instance_type
  zone                      = var.zone
  allow_stopping_for_update = true
  tags                      = ["todo-app"]
  labels                    = local.common_labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.app.id

    access_config {}
  }

  metadata = {
    "enable-oslogin" = "FALSE"
    "ssh-keys"       = "${var.ssh_user}:${trimspace(var.ssh_public_key)}"
  }

  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }

  depends_on = [
    google_compute_firewall.app_ssh,
    google_compute_firewall.app_http,
  ]
}

resource "google_compute_instance" "database" {
  name                      = "${local.deployment_name}-db"
  machine_type              = var.instance_type
  zone                      = var.zone
  allow_stopping_for_update = true
  tags                      = ["todo-db"]
  labels                    = local.common_labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.database.id
  }

  metadata = {
    "enable-oslogin" = "FALSE"
    "ssh-keys"       = "${var.ssh_user}:${trimspace(var.ssh_public_key)}"
  }

  lifecycle {
    ignore_changes = [
      boot_disk[0].initialize_params[0].image,
      attached_disk,
    ]
  }

  depends_on = [
    google_compute_firewall.database_ssh,
    google_compute_firewall.database_mongodb,
    google_compute_router_nat.private_egress,
  ]
}

resource "google_compute_disk" "mongo_data" {
  name   = "${local.deployment_name}-mongo-data"
  type   = "pd-standard"
  zone   = var.zone
  size   = var.mongo_volume_size_gb
  labels = local.common_labels
}

resource "google_compute_disk" "mongo_backup" {
  name   = "${local.deployment_name}-mongo-backup"
  type   = "pd-standard"
  zone   = var.zone
  size   = var.mongo_volume_size_gb
  labels = local.common_labels
}

resource "google_compute_attached_disk" "mongo_data" {
  disk        = google_compute_disk.mongo_data.id
  instance    = google_compute_instance.database.id
  device_name = google_compute_disk.mongo_data.name
  mode        = "READ_WRITE"
}

resource "google_compute_attached_disk" "mongo_backup" {
  disk        = google_compute_disk.mongo_backup.id
  instance    = google_compute_instance.database.id
  device_name = google_compute_disk.mongo_backup.name
  mode        = "READ_WRITE"
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content  = <<-EOT
    [app]
    app-vm ansible_host=${google_compute_instance.app.network_interface[0].access_config[0].nat_ip} ansible_public_ip=${google_compute_instance.app.network_interface[0].access_config[0].nat_ip} ansible_private_ip=${google_compute_instance.app.network_interface[0].network_ip} ansible_user=${var.ssh_user} ansible_ssh_common_args='-o StrictHostKeyChecking=no'

    [db]
    db-vm ansible_host=${google_compute_instance.database.network_interface[0].network_ip} ansible_private_ip=${google_compute_instance.database.network_interface[0].network_ip} ansible_user=${var.ssh_user} ansible_ssh_common_args='-J ${var.ssh_user}@${google_compute_instance.app.network_interface[0].access_config[0].nat_ip} -o StrictHostKeyChecking=no'

    [all:vars]
    ansible_python_interpreter=/usr/bin/python3
    app_public_ip=${google_compute_instance.app.network_interface[0].access_config[0].nat_ip}
    app_private_ip=${google_compute_instance.app.network_interface[0].network_ip}
    db_private_ip=${google_compute_instance.database.network_interface[0].network_ip}
    mongo_volume_name=${google_compute_attached_disk.mongo_data.device_name}
    mongo_backup_volume_name=${google_compute_attached_disk.mongo_backup.device_name}
    instance_name=${var.instance_name}
  EOT
}
