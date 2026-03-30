###############################################################################
# NVA deployment - FortiGate VMSS with internal load balancer
# NewCo hybrid network - hub NVA inspection tier
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Resource group for NVA resources"
  type        = string
}

variable "nva_internal_subnet_id" {
  description = "Subnet ID for NVA internal (trust) interfaces"
  type        = string
}

variable "nva_external_subnet_id" {
  description = "Subnet ID for NVA external (untrust) interfaces"
  type        = string
}

variable "ilb_frontend_ip" {
  description = "Static private IP for the internal load balancer frontend"
  type        = string
  default     = "10.0.1.4"
}

variable "vm_sku" {
  description = "VM size for NVA instances"
  type        = string
  default     = "Standard_F4s_v2"
}

variable "instance_count" {
  description = "Number of NVA instances (minimum 2 for zone redundancy)"
  type        = number
  default     = 2
}

variable "admin_username" {
  description = "Admin username for NVA instances"
  type        = string
  default     = "nvaadmin"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    environment = "production"
    pattern     = "nva-deployment"
    managed-by  = "terraform"
  }
}

###############################################################################
# Internal load balancer (stable next-hop for UDRs)
###############################################################################

resource "azurerm_lb" "nva" {
  name                = "ilb-nva-${var.location}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                          = "nva-frontend"
    subnet_id                     = var.nva_internal_subnet_id
    private_ip_address            = var.ilb_frontend_ip
    private_ip_address_allocation = "Static"
  }
}

resource "azurerm_lb_backend_address_pool" "nva" {
  name            = "nva-backend-pool"
  loadbalancer_id = azurerm_lb.nva.id
}

resource "azurerm_lb_probe" "nva" {
  name                = "nva-health-probe"
  loadbalancer_id     = azurerm_lb.nva.id
  protocol            = "Tcp"
  port                = 8008
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "nva_ha" {
  name                           = "nva-ha-ports"
  loadbalancer_id                = azurerm_lb.nva.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "nva-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.nva.id]
  probe_id                       = azurerm_lb_probe.nva.id
  enable_floating_ip             = true
}

###############################################################################
# NVA VMSS (FortiGate placeholder - replace image reference with your license)
###############################################################################

resource "azurerm_linux_virtual_machine_scale_set" "nva" {
  name                = "vmss-nva-${var.location}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.vm_sku
  instances           = var.instance_count
  admin_username      = var.admin_username
  zones               = ["1", "2", "3"]
  zone_balance        = true
  tags                = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub") # Replace with your key path or use Key Vault
  }

  # Replace with FortiGate or CheckPoint marketplace image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  # Internal (trust) interface
  network_interface {
    name    = "nic-internal"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = var.nva_internal_subnet_id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.nva.id]
    }
  }

  # External (untrust) interface
  network_interface {
    name = "nic-external"

    ip_configuration {
      name      = "external"
      primary   = true
      subnet_id = var.nva_external_subnet_id
    }
  }
}

###############################################################################
# Outputs
###############################################################################

output "ilb_frontend_ip" {
  description = "NVA internal load balancer IP (use as UDR next hop)"
  value       = var.ilb_frontend_ip
}

output "ilb_id" {
  description = "NVA internal load balancer resource ID"
  value       = azurerm_lb.nva.id
}

output "vmss_id" {
  description = "NVA VMSS resource ID"
  value       = azurerm_linux_virtual_machine_scale_set.nva.id
}
