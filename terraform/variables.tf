variable "pm_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox target node name"
  type        = string
}

variable "gateway" {
  description = "Network gateway IP address"
  type        = string
}

variable "control_plane_vip" {
  description = "Control Plane VIP"
  type        = string
}

variable "control_plane_ips" {
  description = "List of control plane node IPs"
  type        = list(string)
}

variable "worker_ips" {
  description = "List of worker node IPs"
  type        = list(string)
}

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "talos_version" {
  description = "Talos version for machine configuration"
  type        = string
}

variable "talos_iso" {
  description = "Proxmox ISO path for Talos (storage:content/filename)"
  type        = string
}

variable "cidr_prefix" {
  description = "CIDR prefix length for node IPs"
  type        = string
  default     = "24"
}

variable "control_plane_disk_size" {
  description = "Disk size for control plane VMs"
  type        = string
  default     = "20G"
}

variable "worker_disk_size" {
  description = "Disk size for worker VMs"
  type        = string
  default     = "50G"
}

variable "nameservers" {
  description = "DNS nameservers for Talos nodes"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}