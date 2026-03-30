# Hybrid DNS resolution

## Overview

Unified name resolution across Azure and on-premises using Azure Private DNS Resolver in the hub VNet, integrated with on-premises Infoblox Grid and Active Directory DNS. Azure workloads resolve on-premises names through conditional forwarding, and branch users resolve Azure Private Link endpoints through the same path in reverse. The hub acts as the DNS transit point, keeping resolution paths consistent with the network inspection model.

<!-- TODO: ![Hybrid DNS architecture](../diagrams/dns-hybrid.svg) -->

---

## Traffic flow

### Azure workload resolving on-premises name

1. **Spoke VM** queries its configured DNS (Azure Private DNS Resolver inbound endpoint in the hub).
2. **Private DNS Resolver** checks Azure Private DNS zones linked to the hub VNet.
3. No match found; **forwarding ruleset** matches the on-premises domain (`corp.newco.com`) and forwards to the **Infoblox Grid VIP** on-premises.
4. Query travels through the **hub NVA** (if DNS traffic inspection is enabled) and **ExpressRoute** to the branch.
5. **Infoblox Grid** resolves from AD-integrated zones or authoritative zone data and returns the answer.

### On-premises client resolving Azure Private Link endpoint

1. **Branch client** queries `storage.blob.core.windows.net` through the **Infoblox Grid**.
2. **Infoblox conditional forwarder** for `privatelink.blob.core.windows.net` sends the query to the **Azure Private DNS Resolver inbound endpoint** via ExpressRoute.
3. **Private DNS Resolver** resolves from the `privatelink.blob.core.windows.net` private zone linked to the hub VNet.
4. Response returns the private IP of the storage account's private endpoint in the spoke.

### Spoke-to-spoke resolution

1. **Spoke A VM** queries a name hosted in a private DNS zone linked to another spoke.
2. Because all private zones are linked to the hub VNet, the **Private DNS Resolver** resolves directly from the zone without forwarding.

---

## Key components

| Component | Role | Azure resource |
|-----------|------|----------------|
| Azure Private DNS Resolver | Inbound/outbound DNS resolution in hub | `Microsoft.Network/dnsResolvers` |
| Inbound endpoint | Receives queries from on-premises and spokes | `Microsoft.Network/dnsResolvers/inboundEndpoints` |
| Outbound endpoint | Forwards queries to on-premises DNS | `Microsoft.Network/dnsResolvers/outboundEndpoints` |
| DNS forwarding ruleset | Conditional forwarding rules per domain | `Microsoft.Network/dnsForwardingRulesets` |
| Azure Private DNS zones | Host private link and custom zone records | `Microsoft.Network/privateDnsZones` |
| VNet links | Attach private zones to hub and spoke VNets | `Microsoft.Network/privateDnsZones/virtualNetworkLinks` |
| Infoblox Grid (on-prem) | Authoritative DNS, IPAM, AD-integrated zones | On-premises appliance |

---

## Routing

DNS traffic (UDP/TCP 53) follows the same UDR paths as all other traffic:

| Scope | Prefix | Next hop | Notes |
|-------|--------|----------|-------|
| Spoke UDR | Hub DNS Resolver subnet | Hub NVA ILB | DNS queries from spokes through NVA (optional) |
| Hub NVA UDR | On-prem DNS CIDRs | ExpressRoute gateway | Forwarded queries to Infoblox |

> If DNS traffic inspection is not required, spoke VNets can be linked directly to the forwarding ruleset, bypassing the NVA for DNS. This reduces latency for name resolution.

---

## Private DNS zone inventory

| Zone | Purpose |
|------|---------|
| `privatelink.blob.core.windows.net` | Storage account private endpoints |
| `privatelink.database.windows.net` | Azure SQL private endpoints |
| `privatelink.vaultcore.azure.net` | Key Vault private endpoints |
| `privatelink.azurecr.io` | Container Registry private endpoints |
| `corp.newco.com` | Forwarded to on-prem Infoblox (not hosted in Azure) |
| `azure.newco.com` | Custom zone for Azure-hosted service records |

---

## Implementation notes

### Private DNS Resolver sizing

Each inbound or outbound endpoint supports up to 10,000 queries per second. For most hybrid deployments, a single instance per region is sufficient. Deploy in both Central US and East US 2 hubs for regional redundancy.

### Zone linking strategy

Link all `privatelink.*` zones to the hub VNet. Link application-specific custom zones to both hub and relevant spoke VNets. Avoid linking zones to spokes that do not need them to limit the resolution scope.

### Infoblox integration

Configure Infoblox Grid members with conditional forwarders pointing to the Azure Private DNS Resolver inbound endpoint IP. Use Infoblox DNS Traffic Control (DTC) to load balance across resolver endpoints in both regions.

### Bicep snippet (Private DNS Resolver)

```bicep
param location string = resourceGroup().location
param hubVnetId string

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: 'newco-dns-resolver'
  location: location
  properties: {
    virtualNetwork: { id: hubVnetId }
  }
}

resource inbound 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: resolver
  name: 'inbound'
  location: location
  properties: {
    ipConfigurations: [
      {
        subnet: { id: '${hubVnetId}/subnets/dns-resolver-inbound' }
      }
    ]
  }
}
```

---

## Security considerations

- **Zero Trust alignment (NIST SP 800-207):** DNS resolution is centralized through the hub, preventing spokes from directly querying external or on-premises DNS servers. All resolution paths are auditable.
- **DNS exfiltration:** Monitor query logs for unusually long subdomain labels or high query volumes to a single domain, which may indicate DNS tunneling. Azure Private DNS Resolver logs integrate with Log Analytics.
- **Split-brain avoidance:** Ensure on-premises and Azure zones do not overlap. Use distinct subdomains (`azure.newco.com` vs `corp.newco.com`) to prevent conflicting answers.
- **Logging:** Enable diagnostic settings on the Private DNS Resolver and all private DNS zones. Correlate with NVA DNS inspection logs for full query visibility.
- **Zone access control:** Use Azure RBAC to restrict who can modify private DNS zones and VNet links. Unauthorized zone changes could redirect traffic to malicious endpoints.

---

## Related patterns

- [Branch to Azure](branch-to-azure.md) - ExpressRoute path used for DNS forwarding to on-premises
- [Front Door ingress](front-door-ingress.md) - custom domain DNS (public) complements private DNS resolution
- [NetBox integration](netbox-integration.md) - IPAM data in NetBox feeds subnet and DNS zone planning
