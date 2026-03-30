# NetBox IRM platform integration

## Overview

NetBox serves as the infrastructure resource management (IRM) source of truth for IP address management, circuit tracking, and device inventory across the hybrid Azure network. Deployed in the hub VNet shared-services subnet, NetBox provides an API-driven single pane for all network resource data, feeding Terraform provisioning pipelines and operational dashboards.

<!-- TODO: ![NetBox integration architecture](../diagrams/netbox-integration.svg) -->

---

## Architecture

NetBox runs as a containerized deployment (Docker Compose or Kubernetes) in the shared-services subnet of the hub VNet. It is accessible only through the hub NVA and internal load balancer. CI/CD pipelines in GitHub Actions query the NetBox API to retrieve prefix allocations before provisioning Azure resources via Terraform.

---

## Key components

| Component | Role | Platform |
|-----------|------|----------|
| NetBox application | IRM, IPAM, circuit and device tracking | Hub VNet shared-services subnet |
| PostgreSQL | NetBox backend database | Co-located or Azure Database for PostgreSQL |
| Redis | NetBox caching and task queue | Co-located or Azure Cache for Redis |
| Internal load balancer | Stable endpoint for NetBox API | Azure `Microsoft.Network/loadBalancers` |
| GitHub Actions | CI/CD pipeline consuming NetBox API | GitHub |
| Terraform | Infrastructure provisioning from NetBox data | CI/CD runner |
| NSG | Restrict NetBox access to authorized subnets | Azure `Microsoft.Network/networkSecurityGroups` |

---

## IPAM workflow

### Prefix hierarchy

| Level | Example | NetBox object | Purpose |
|-------|---------|---------------|---------|
| Region supernet | `10.0.0.0/8` | Aggregate | Top-level allocation boundary |
| Hub VNet | `10.0.0.0/16` | Prefix (container) | Hub address space |
| Hub subnet | `10.0.1.0/24` | Prefix (active) | NVA inspection subnet |
| Spoke VNet | `10.1.0.0/16` | Prefix (container) | Spoke address space |
| Spoke subnet | `10.1.1.0/24` | Prefix (active) | Workload subnet |

### New spoke provisioning flow

1. **Network engineer** requests a new spoke VNet in NetBox, selecting the next available /16 from the region supernet.
2. **NetBox** allocates the prefix and assigns child subnets (/24) for workload, private endpoints, and management.
3. **Terraform pipeline** runs, querying NetBox API for the allocated prefixes via the `netbox` provider data sources.
4. **Terraform** provisions the spoke VNet, subnets, peering to hub, UDRs, and NSGs using the NetBox-sourced CIDRs.
5. **Post-provisioning webhook** updates the NetBox prefix status from `reserved` to `active` and tags it with the Azure subscription ID.

---

## Circuit tracking

| Field | Example value | Purpose |
|-------|--------------|---------|
| Circuit provider | Equinix | Carrier identification |
| Circuit ID | ECX-CUS-001 | Provider reference number |
| Circuit type | ExpressRoute | Connectivity technology |
| A-side | Equinix DA1 (Dallas) | Provider edge location |
| Z-side | Azure Central US | Azure peering location |
| Bandwidth | 1 Gbps | Provisioned capacity |
| Status | Active | Operational state |

Track ExpressRoute circuits, SD-WAN overlays, and Equinix ECX Fabric virtual connections as circuit objects. Link circuits to the hub site and NVA device records for dependency mapping.

---

## Device inventory

Track NVA instances, ExpressRoute gateways, and DNS resolvers as device objects in NetBox:

| Device role | Example | Tracked attributes |
|-------------|---------|-------------------|
| NVA (firewall) | FortiGate VMSS instance | Serial, firmware version, interfaces, assigned hub |
| ER gateway | Hub ER virtual network gateway | SKU, provisioned bandwidth, linked circuits |
| DNS resolver | Azure Private DNS Resolver | Inbound/outbound endpoint IPs, linked VNets |
| Load balancer | Hub NVA ILB | Frontend IP, backend pool members |

---

## Implementation notes

### Terraform integration

Use the `e-breuninger/netbox` Terraform provider to query prefix allocations at plan time:

```hcl
data "netbox_prefix" "spoke" {
  cidr = var.spoke_cidr
}

resource "azurerm_virtual_network" "spoke" {
  name                = "spoke-${var.workload_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [data.netbox_prefix.spoke.cidr]
}
```

### Webhooks

Configure NetBox webhooks to notify the CI/CD pipeline when prefix status changes. This enables automated drift detection: if a VNet is deleted in Azure but the prefix remains active in NetBox, the pipeline flags the discrepancy.

### Backup and DR

Back up the PostgreSQL database to Azure Blob Storage on a daily schedule. In a regional failure, restore NetBox in the East US 2 hub from the latest backup. NetBox is not in the critical data path, so RTO can be relaxed (< 4 hours).

---

## Security considerations

- **Zero Trust alignment (NIST SP 800-207):** NetBox API access is restricted by NSG to authorized subnets (CI/CD runners, network team jump boxes). API authentication uses tokens with scoped permissions per integration.
- **Data sensitivity:** NetBox contains the complete IP plan and network topology. Treat it as confidential infrastructure data. Restrict read access to network and security teams.
- **API token rotation:** Rotate NetBox API tokens on a 90-day cycle. Store tokens in Azure Key Vault and inject them into CI/CD pipelines as secrets.
- **Audit logging:** Enable NetBox change logging to track all IPAM modifications. Forward logs to Log Analytics for correlation with infrastructure changes.
- **Network isolation:** NetBox sits in the shared-services subnet behind the hub NVA. It has no public IP and is not reachable from spoke workloads without explicit NSG rules.

---

## Related patterns

- [Branch to Azure](branch-to-azure.md) - circuits tracked in NetBox connect branches to the hub
- [Hybrid DNS](dns-hybrid.md) - DNS zone planning informed by NetBox IPAM data
- [Multi-cloud connectivity](multi-cloud-connectivity.md) - Equinix circuits managed as NetBox circuit objects
