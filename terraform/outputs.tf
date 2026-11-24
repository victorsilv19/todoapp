output "app_public_ipv4_address" {
  description = "Public IPv4 address of the application VM."
  value       = google_compute_instance.app.network_interface[0].access_config[0].nat_ip
}

output "app_private_ipv4_address" {
  description = "Private VPC address of the application VM."
  value       = google_compute_instance.app.network_interface[0].network_ip
}

output "db_private_ipv4_address" {
  description = "Private VPC address of the database VM."
  value       = google_compute_instance.database.network_interface[0].network_ip
}

output "mongo_volume_name" {
  description = "Device name of the persistent data disk attached to the database VM."
  value       = google_compute_attached_disk.mongo_data.device_name
}

output "mongo_backup_volume_name" {
  description = "Device name of the separate persistent backup disk."
  value       = google_compute_attached_disk.mongo_backup.device_name
}

output "application_url" {
  description = "HTTPS URL of the application; browsers will warn because its certificate is self-signed."
  value       = "https://${google_compute_instance.app.network_interface[0].access_config[0].nat_ip}"
}

output "deployment_id" {
  description = "Deployment identity used to confirm the target before destroying resources."
  value       = "${var.instance_name}-${var.environment}"
}

output "estimated_persistent_disk_gb" {
  description = "Total boot, database, and backup disk allocation in GiB."
  value       = (2 * var.boot_disk_size_gb) + (2 * var.mongo_volume_size_gb)
}
