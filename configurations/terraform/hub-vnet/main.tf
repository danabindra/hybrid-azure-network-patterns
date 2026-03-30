###############################################################################
# Hub VNet with gateway, NVA, and shared-services subnets
# NewCo hybrid network - Central US primary region
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
  description = "Azure region for the hub VNet"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Resource group for hub networking resources"
  type        = string
}

variable "hub_address_space" {
  description = "Address space for the hub VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Hub subnet definitions"
  type = map(object({
    address_prefix = string
  }))
  default = {
    GatewaySubnet = { address_prefix = "10.0.255.0/27" }
    nva-internal  = { address_prefix = "10.0.1.0/24" }
    nva-external  = { address_prefix = "10.0.2.0/24" }
    shared-services = { address_prefix = "10.0.3.0/24" }
    dns-resolver-inbound  = { address_prefix = "10.0.4.0/28" }
    dns-resolver-outbound = { address_prefix = "10.0.4.16/28" }
  }
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    environment = "production"
    pattern     = "hub-vnet"
    managed-by  = "terraform"
  }
}

###############################################################################
# Hub VNet
###############################################################################

resource "azurerm_virtual_network" "hub" {
  name                = "hub-vnet-${var.location}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.hub_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "hub" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value.address_prefix]
}

###############################################################################
# NSG - deny-by-default on non-gateway subnets
###############################################################################

resource "azurerm_network_security_group" "hub" {
  for_each = {
    for k, v in var.subnets : k => v if k != "GatewaySubnet"
  }

  name                = "nsg-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "hub" {
  for_each = {
    for k, v in var.subnets : k => v if k != "GatewaySubnet"
  }

  subnet_id                 = azurerm_subnet.hub[each.key].id
  network_security_group_id = azurerm_network_security_group.hub[each.key].id
}

###############################################################################
# Outputs
###############################################################################

output "hub_vnet_id" {
  description = "Hub VNet resource ID"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  description = "Hub VNet name"
  value       = azurerm_virtual_network.hub.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value       = { for k, v in azurerm_subnet.hub : k => v.id }
}

output "nva_internal_subnet_id" {
  description = "NVA internal subnet ID (for ILB and VMSS)"
  value       = azurerm_subnet.hub["nva-internal"].id
}
