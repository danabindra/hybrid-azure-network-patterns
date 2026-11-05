# ADR-0003: Management plane for the Palo Alto Cloud NGFW estate

**Status:** Accepted
**Date:** [confirm]
**Decision owner:** Lead Enterprise Architect
**Workstream:** Security / Management

---

## Context

ADR-0002 established Palo Alto Cloud NGFW as the firewall in prod and non-prod. The estate
needs a management plane for security policy authoring, distribution, and logging. Palo Alto
Cloud NGFW supports two models: cloud-managed rulestacks through Strata Cloud Manager, or
Panorama-managed rulestacks using a customer-run Panorama. Because NewCo is separating
from ParentCo, NewCo is building greenfield on a divestiture timeline and cannot
lean on parent management infrastructure.

## Decision

Manage Cloud NGFW policy through Strata Cloud Manager (cloud-managed rulestacks), not a
customer-run Panorama.

## Options considered

| Option | Summary | Pros | Cons |
|---|---|---|---|
| Strata Cloud Manager (chosen) | Palo's cloud-delivered management, cloud-managed rulestacks | No Panorama to deploy, size, patch, HA, or back up; fast greenfield standup; unified Strata console; scales with the estate | Recurring subscription; less of the deepest Panorama feature set; dependency on the SaaS control plane and its supported regions |
| Panorama (bring your own) | Customer-run Panorama appliance manages rulestacks | Full Panorama feature depth; consistent if the broader estate is Panorama-managed; centralized multi-firewall management | Must deploy, size, patch, HA, and back up Panorama; slower standup; ongoing operational burden |

Panorama was rejected primarily on standup speed and operational burden for a standalone
entity building from zero against a separation deadline.

## Consequences

**Positive**
- No Panorama appliance to run, patch, or make highly available.
- Fast standup that suits the greenfield, divestiture-timeline build.
- Maintenance and upgrade burden for the management plane shifts to the vendor.
- Scales with the Cloud NGFW estate without re-architecting management.

**Negative / costs**
- Recurring subscription cost.
- Reliance on the Strata control plane's availability and supported regions.
- Less of the deepest Panorama capability set, which matters if requirements later demand it.

**Second-order effects**
- Logging integrates with the Strata Logging Service and/or Azure Log Analytics. A SIEM
  is not in scope at this time, so SIEM integration is a separate, deferred question.
- The disaster-recovery story for management depends on Strata's regional resilience rather
  than something NewCo operates directly.
- If any other part of the organization standardizes on Panorama later, there is a
  consistency question to revisit.

## Security boundary impact

- **Admin access path:** Because Cloud NGFW is a managed service and Strata is SaaS,
  administration is through the Strata tenant and Azure RBAC on the Cloud NGFW resource,
  not SSH or HTTPS to customer instances. Access control therefore lives at the Strata
  tenant and Azure RBAC layer, which is where to enforce least privilege.
- **Gateway VNet vs security VNet separation:** Unaffected. This decision governs how the
  firewall is administered, not the data path, so the boundary separation required by
  Celestis (security architecture) holds.
- **Routing:** No effect on BGP at ASN 65515 or the VpnGw3AZ active-active gateway design.

## Stakeholders to align

| Stakeholder | Interest / likely objection | Align before or inform after |
|---|---|---|
| NewCo Network Engineering (Fenrier, Helion) | Own the Cloud NGFW and its policy plane; primary operators | Align before |
| Celestis (security architecture) | Admin-path access control vs the boundary model | Align before |
| Iris (Terraform and DevOps) | Terraform for the Cloud NGFW resource, Strata association, and RBAC | Align before |
| Lunara, Hummin | Subscription cost basis | Inform with rationale |

## Open questions / follow-ups

- Set log retention and the logging destination (Strata Logging Service vs Azure Log
  Analytics).
- Confirm Strata region selection and data-residency expectations.
- Confirm the rulestack structure (shared vs per-environment for prod and non-prod).
- Confirm whether any existing ParentCo Panorama footprint influenced or constrains this.

## References

- ADR-0002 (Palo Alto Cloud NGFW as the firewall in prod and non-prod).
- Azure hub-and-spoke reference architecture repo.
