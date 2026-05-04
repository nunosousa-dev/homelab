terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc07"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}

provider "proxmox" {
  pm_api_url          = "https://10.0.0.2:8006/api2/json"
  pm_api_token_id     = "terraform-prov@pve!api"
  pm_api_token_secret = "c7996046-12c3-4ad1-a9d7-dd4941905754"
  pm_tls_insecure     = true
}

provider "talos" {}
