---
template: home.html
---

# Hybrid Azure Network Patterns

Production-tested network architecture patterns for enterprise Azure deployments with hub-spoke topology, NVA security inspection, hybrid connectivity, and multi-region resilience.

## Patterns

| Pattern | Description |
| --------- | ------------- |
| [Branch to Azure](patterns/branch-to-azure.md) | ExpressRoute and SD-WAN connectivity from enterprise branches through hub NVA inspection |
| [Internet egress](patterns/internet-egress.md) | Centralized outbound internet access through hub NVA with NAT Gateway |
| [Front Door ingress](patterns/front-door-ingress.md) | Global inbound web traffic via Azure Front Door with WAF and Private Link origin cloaking |
| [Region-to-region transit](patterns/region-transit.md) | Multi-region traffic with dual NVA inspection and global VNet peering |
| [Multi-cloud connectivity](patterns/multi-cloud-connectivity.md) | Private cross-cloud connectivity to OCI via Equinix ECX Fabric |
| [Hybrid DNS](patterns/dns-hybrid.md) | Azure Private DNS Resolver with on-premises Infoblox and AD integration |
| [NetBox integration](patterns/netbox-integration.md) | Infrastructure resource management for IPAM, circuits, and device inventory |

## Architecture context

- **Topology:** Traditional hub-spoke (not Virtual WAN), dual-region (Central US primary, East US 2 secondary)
- **Security:** NVA inspection at hub (FortiGate or CheckPoint VMSS, active-active)
- **Connectivity:** ExpressRoute via Equinix primary, S2S VPN backup, SD-WAN overlay
- **Segmentation:** Frontend/backend VNet separation per region, no spoke-to-spoke peering
- **Compliance:** NIST SP 800-207 (Zero Trust), SOC 2, PCI DSS considerations

## Additional resources

- [NIST SP 800-207 control mapping](compliance/nist-800-207.md)
- [Terraform modules](https://github.com/danabindra/hybrid-azure-network-patterns/tree/main/configurations/terraform) for hub VNet, spoke VNet, and NVA deployment
