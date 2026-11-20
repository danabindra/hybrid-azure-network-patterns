# ADR-0002: Use Palo Alto Cloud NGFW for inspection in prod and non-prod

**Status:** Accepted
**Date:** [confirm]
**Decision owner:** Lead Enterprise Architect
**Workstream:** Security / Connectivity

---

## Context

NewCo is separating from ParentCo into a standalone company and needs its own
Azure landing zone with centralized NGFW inspection for north-south and east-west traffic,
consistent across prod and non-prod. The platform had to fit the hub-and-spoke design and
the team's Palo Alto operating model without standing up and sustaining a self-managed
firewall fleet on a divestiture timeline.

## Decision

Use Palo Alto Cloud NGFW for Azure, the managed cloud-native NGFW service, in both prod
and non-prod. It is deployed in the security VNet [confirm: VNet-based hub deployment vs
Azure Virtual WAN integration], policy is managed via Strata Cloud Manager (see ADR-0003),
and all in-scope traffic is steered through it by UDR for zero-bypass.

## Options considered

| Option | Summary | Pros | Cons |
|---|---|---|---|
| Palo Alto Cloud NGFW (chosen) | Managed SaaS NGFW, Palo operates and scales the firewall | No firewall fleet to size, patch, or autoscale; native Azure Marketplace integration; Strata Cloud Manager policy; uniform across prod and non-prod | Recurring Marketplace consumption cost; less low-level control; constrained by supported deployment and integration models; dependency on the managed service |
| Palo Alto VM-Series on VMSS | Customer-run Palo firewalls as an NVA | Full control; mature; flexible routing including BGP | Customer owns sizing, patching, HA, autoscale, and lifecycle; higher operational burden |
| Azure Firewall (native) | Azure-managed firewall | Simplest, native, no separate licensing | App-ID and threat-prevention depth gaps vs Palo; diverges from the team's Palo standardization |

[Confirm the alternatives that were actually evaluated. The above is the realistic
Palo-centric option set, not a verified record of the room.]

## Consequences

**Positive**
- No customer-run firewall fleet to size, patch, scale, or DR. Palo operates the data
  plane and autoscaling.
- Uniform inspection posture across prod and non-prod.
- Integrates with Strata Cloud Manager for policy authoring and distribution.
- Marketplace billing, no separate license procurement to run.

**Negative / costs**
- Recurring consumption cost that scales with throughput.
- Less granular control than self-managed VM-Series.
- Bounded by the supported Cloud NGFW deployment and integration models in Azure.
- Dependency on the managed service's regional availability.

**Second-order effects**
- The routing design must steer traffic to the Cloud NGFW by UDR and disable gateway route
  propagation on spokes to guarantee zero-bypass.
- The management-plane choice follows directly from this and is captured in ADR-0003
  (Strata Cloud Manager over Panorama for rulestack management).
- Logging integrates with Azure Log Analytics and/or the Strata Logging Service. A SIEM
  is not in scope at this time, so any SIEM design is a separate, deferred question.
- Because there is no customer VMSS, the concerns of an ILB in front of an NVA and
  SSH access to instances do not apply. They are replaced by managed-service access and
  identity concerns.

## Security boundary impact

- **Gateway VNet vs security VNet separation:** Maintained per the security architecture
  requirement owned by Celestis. The Cloud NGFW lives in the security VNet [confirm],
  separate from the Gateway VNet that holds the VPN Gateway and Azure Route Server.
- **Zero-bypass enforcement:** All in-scope prod and non-prod traffic is steered through
  the Cloud NGFW via UDR, with gateway route propagation disabled on spoke subnets. Any
  path that avoids the Cloud NGFW is a flag, not a footnote.
- **Routing relationship, FLAG:** An earlier design assumed an NVA peering BGP with Azure
  Route Server at ASN 65515. A managed Cloud NGFW is typically reached by UDR rather than
  by peering as a BGP speaker. Confirm whether Route Server BGP applies only to the gateway
  layer (VPN, future ExpressRoute) while the firewall is UDR-steered, or whether the design
  peers the firewall.

## Stakeholders to align

| Stakeholder | Interest / likely objection | Align before or inform after |
|---|---|---|
| Celestis (security architecture) | Security boundary separation must hold | Align before |
| Iris (Terraform and DevOps) | Provisions the Cloud NGFW, UDRs, Marketplace plan | Align before |
| NewCo Network Engineering (Fenrier, Helion) | Own the Cloud NGFW, the Strata Cloud Manager tenant, and policy authoring | Align before |
| Lunara, Hummin, Glynsera, Stellarys | Consumption cost and capacity posture | Inform with rationale |

## Open questions / follow-ups

- Confirm deployment model: VNet-based hub vs Azure Virtual WAN.
- Resolve the Route Server BGP vs UDR-only steering question above.
- Confirm the alternatives that were formally evaluated.
- Confirm the decision date.

## References

- ADR-0003 (Strata Cloud Manager over Panorama for Cloud NGFW policy management).
- Azure hub-and-spoke reference architecture repo.
- Landing zone traffic-flow diagram (to be reconciled to the Cloud NGFW data path).
