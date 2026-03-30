###############################################################################
# Spoke VNet with hub peering and UDR forcing traffic through NVA
# NewCo hybrid network
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
  description = "Azure region for the spoke VNet"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Resource group for spoke networking resources"
  type        = string
}

variable "spoke_name" {
  description = "Short name for the spoke (used in resource names)"
  type        = string
}

variable "spoke_address_space" {
  description = "Address space for the spoke VNet"
  type        = string
}

variable "subnets" {
  description = "Spoke subnet definitions"
  type = map(object({
    address_prefix = string
  }))
}

variable "hub_vnet_id" {
  description = "Hub VNet resource ID for peering"
  type        = string
}

variable "hub_vnet_name" {
  description = "Hub VNet name for peering"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Hub VNet resource group name"
  type        = string
}

variable "nva_ilb_ip" {
  description = "Hub NVA internal load balancer private IP (UDR next hop)"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    environment = "production"
    pattern     = "spoke-vnet"
    managed-by  = "terraform"
  }
}

###############################################################################
# Spoke VNet
###############################################################################

resource "azurerm_virtual_network" "spoke" {
  name                = "spoke-${var.spoke_name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.spoke_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [each.value.address_prefix]
}

###############################################################################
# UDR - force all traffic through hub NVA
###############################################################################

resource "azurerm_route_table" "spoke" {
  name                          = "rt-spoke-${var.spoke_name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  disable_bgp_route_propagation = true
  tags                          = var.tags

  route {
    name                   = "default-to-nva"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.nva_ilb_ip
  }
}

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each = var.subnets

  subnet_id      = azurerm_subnet.spoke[each.key].id
  route_table_id = azurerm_route_table.spoke.id
}

###############################################################################
# NSG - deny-by-default
###############################################################################

resource "azurerm_network_security_group" "spoke" {
  name                = "nsg-spoke-${var.spoke_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "spoke" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.spoke[each.key].id
  network_security_group_id = azurerm_network_security_group.spoke.id
}

###############################################################################
# VNet peering (spoke -> hub and hub -> spoke)
###############################################################################

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${var.spoke_name}-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = var.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${var.spoke_name}"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

###############################################################################
# Outputs
###############################################################################

output "spoke_vnet_id" {
  description = "Spoke VNet resource ID"
  value       = azurerm_virtual_network.spoke.id
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value       = { for k, v in azurerm_subnet.spoke : k => v.id }
}

output "route_table_id" {
  description = "Spoke route table ID"
  value       = azurerm_route_table.spoke.id
}
