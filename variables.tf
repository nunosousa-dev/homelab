variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
}

variable "control_plane_ip" {
  description = "Control Plane IP"
  type        = string
}

variable "node_1_ip" {
  description = "Node 1 IP"
  type        = string
}

variable "node_2_ip" {
  description = "Node 2 IP"
  type        = string
}