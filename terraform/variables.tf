variable "project_id" {
  description = "Google Cloud project ID that owns the deployment."
  type        = string
}

variable "region" {
  description = "Google Cloud region for the network, router, NAT, and subnetworks."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone for the virtual machines and persistent disks."
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "homolog", "prod"], var.environment)
    error_message = "environment must be dev, homolog, or prod."
  }
}

variable "instance_name" {
  description = "Base name used for Google Cloud resources."
  type        = string
  default     = "vm-todo-pm04"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must use lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "instance_type" {
  description = "Compute Engine machine type used by both virtual machines."
  type        = string
  default     = "e2-medium"

  validation {
    condition     = contains(["e2-small", "e2-medium", "e2-standard-2"], var.instance_type)
    error_message = "instance_type must be e2-small, e2-medium, or e2-standard-2."
  }
}

variable "ubuntu_version" {
  description = "Ubuntu LTS image family used to create the virtual machines."
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "ssh_user" {
  description = "Linux account used for SSH and Ansible."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "OpenSSH public key injected into both instances through instance metadata."
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(trimspace(var.ssh_public_key), "ssh-ed25519 ")
    error_message = "ssh_public_key must be an OpenSSH ed25519 public key."
  }
}

variable "app_subnet_cidr" {
  description = "IPv4 range for the application subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "database_subnet_cidr" {
  description = "IPv4 range for the private database subnet."
  type        = string
  default     = "10.20.2.0/24"
}

variable "boot_disk_size_gb" {
  description = "Boot disk capacity for each VM in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "mongo_volume_size_gb" {
  description = "Capacity of each separate MongoDB data and backup persistent disk in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.mongo_volume_size_gb >= 10
    error_message = "mongo_volume_size_gb must be at least 10 GiB."
  }
}

variable "docker_image" {
  description = "Docker image name prefix for the versioned frontend and API images."
  type        = string
  default     = "todo-app"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*$", var.docker_image))
    error_message = "docker_image must be a lowercase Docker-compatible image name prefix."
  }
}

variable "docker_tag" {
  description = "Explicit release tag applied to both application images."
  type        = string
  default     = "1.0.0"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.docker_tag))
    error_message = "docker_tag must be a valid explicit Docker tag."
  }
}
