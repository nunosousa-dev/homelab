variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
}

variable "control_plane1_ip" {
  description = "Control Plane IP"
  type        = string
}

variable "control_plane2_ip" {
  description = "Control Plane IP"
  type        = string
}

variable "control_plane3_ip" {
  description = "Control Plane IP"
  type        = string
}

variable "node1_ip" {
  description = "Node 1 IP"
  type        = string
}

variable "node2_ip" {
  description = "Node 2 IP"
  type        = string
}
