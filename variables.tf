variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
}

variable "control_plane_vip" {
  description = "Control Plane VIP"
  type        = string
}

variable "control_plane_cidr" {
  description = "Control Plane IP"
  type        = string
}

variable "node1_cidr" {
  description = "Node 1 IP"
  type        = string
}

variable "gateway" {
  description = "Network gateway IP address"
  type = string
}