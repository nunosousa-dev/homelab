variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
}

variable "control_plane1_cidr" {
  description = "Control Plane IP"
  type        = string
}

variable "control_plane2_cidr" {
  description = "Control Plane IP"
  type        = string
}

variable "control_plane3_cidr" {
  description = "Control Plane IP"
  type        = string
}

variable "node1_cidr" {
  description = "Node 1 IP"
  type        = string
}

variable "node2_cidr" {
  description = "Node 2 IP"
  type        = string
}

variable "gateway" {
  description = "Network gateway IP address"
  type = string
}