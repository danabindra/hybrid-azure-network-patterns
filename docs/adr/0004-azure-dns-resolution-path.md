# ADR-0004: DNS Resolution Path for NewCo Azure Workloads

**Status:** Proposed
**Date:** 2026-07-23
**Deciders:** Lead Enterprise Architect (author), Hummin (engagement lead), NewCo Network, ParentCo Network (Glynsera), InfoSec
**Supersedes:** none
**Related artifacts:** anycast DNS forced tunnel diagram, Azure IP address plan, hub-spoke LLD

---

## Context

NewCo is separating from ParentCo into a standalone entity. The Azure landing zone is a greenfield hub-spoke build with the following constraints already agreed:

- Gateway VNet and the Palo Alto VNet are separate security boundaries.
- Zero-bypass UDR enforcement. Every flow leaving a spoke is routed to the Cloud NGFW.
- VPN Gateway today with **static local network gateway address space**. There is no Azure Route Server. Every on-premises destination prefix is manually enumerated.
- ExpressRoute is planned for a later phase, at which point prefixes arrive over BGP instead.
- Internet egress is via Zscaler ZIA.

ParentCo operates an internal recursive DNS service published as a single anycast VIP, 172.16.53.53, announced as a /32 by BGP from dozens of sites globally. Each site fronts a load balanced pool of recursive resolvers. Because the VIP is RFC1918, it is reachable only across the private WAN, not the public internet.

Azure workloads need to resolve three distinct classes of name:

1. ParentCo and NewCo internal namespaces held on the on-premises recursive service.
2. Azure Private DNS zones, including `privatelink.*` records for Private Endpoints in the NewCo tenant.
3. Public internet names.

The forces in tension are:

- **Divestiture clock.** Any dependency on ParentCo resolvers is time-boxed to the TSA period and has to be exit-ready.
- **Static routing today.** Anything the design depends on reaching must be added to the local network gateway address space by hand, and that list is a change-control item.
- **Inspection mandate.** DNS is a recognised exfiltration channel. Security wants the flow visible to the NGFW.
- **Spoke growth.** The spoke count will keep climbing through migration waves, so per-spoke manual configuration is a scaling liability.
- **Tenant boundary.** NewCo and ParentCo are separate Entra tenants, and Microsoft does not support cross-tenant linking of DNS forwarding rulesets.

---

## Decision

Deploy **Azure DNS Private Resolver in the hub, with the DNS forwarding ruleset linked directly to each spoke VNet**. This is Microsoft's second reference pattern in the private resolver architecture guidance.

Concretely:

- Workload VNets keep the default DNS server setting, Azure-provided DNS at 168.63.129.16. No custom DNS server is configured on any VNet or NIC.
- The forwarding ruleset is linked to each spoke VNet. Rules forward the specific ParentCo and NewCo internal suffixes to 172.16.53.53.
- **No `.` catchall rule.** Namespaces that do not match a rule fall through to Azure-provided DNS, so public resolution stays inside Azure and does not depend on ParentCo.
- Azure Private DNS zones are linked to the spokes and resolve natively, ahead of any forwarding.
- Forwarded queries egress from the outbound endpoint subnet in the hub. That subnet carries an explicit UDR for 172.16.53.53/32 with the Cloud NGFW as next hop, overriding the gateway-propagated system route.
- 172.16.53.53/32 is added to the local network gateway address space now, and to the ExpressRoute advertisement set at cutover.

---

## Options Considered

### Option 1: Direct query to the anycast VIP over the forced tunnel

**This is the design in the current diagram, and it is the option most likely to be proposed in the room because it is the simplest thing that appears to work.** It deserves a full hearing before it is set aside.

Workload VNets set their DNS server to 172.16.53.53. The VM originates packets to the VIP directly. The spoke UDR, whether the 0.0.0.0/0 default or a specific /32, carries them to the NGFW, then out the gateway to the on-premises router. The on-premises load balancer distributes to a resolver node, and BGP has already decided which site is nearest.

| Dimension | Assessment |
|---|---|
| Complexity | Low. No new Azure resource at all. |
| Cost | Lowest. No resolver charges, no endpoint subnets. |
| Scalability | Poor. DNS server setting is per VNet and per NIC, so every new spoke is a manual touch and a VM restart to take effect. |
| Team familiarity | High. This is the classic pre-resolver pattern everyone has built before. |
| Inspection | Good. The full query is a spoke-sourced flow through the NGFW with the real client IP intact. |
| Exit readiness | Poor. Every VNet in the estate is hard-coded to a ParentCo-owned address. |

**Pros**

- Nothing new to deploy, nothing new to operate, nothing new to explain to InfoSec.
- The NGFW sees the actual workload IP as the source, which is the best possible logging outcome.
- One destination prefix to add to the local network gateway.
- Works identically before and after the ExpressRoute cutover.

**Cons**

- **This is the disqualifier: Azure Private DNS zones stop resolving.** Once a VM points at an on-premises resolver, `privatelink.blob.core.windows.net` and every other Private Endpoint FQDN goes to ParentCo, which has no record for it. Fixing that requires ParentCo to conditional-forward those zones back into the NewCo tenant, which means asking InfoSec for a cross-tenant path. That is the same category of request that was previously denied on a cross-tenant data platform workstream. Building the DNS design on top of an already-denied dependency is not a position worth arguing from.
- All public name resolution for NewCo Azure workloads leaves the tenant and depends on ParentCo infrastructure through the TSA and beyond.
- Every spoke is hard-coded to a ParentCo-owned VIP, so divestiture cutover is an estate-wide reconfiguration with a reboot per VM.
- Complete outage of name resolution if the tunnel or the on-premises path drops. There is no local fallback.

### Option 2: Private Resolver, ruleset linked to the hub, spokes point at the inbound endpoint

Microsoft's first reference pattern. Spoke VNets set their DNS server to the inbound endpoint IP in the hub. The resolver evaluates the ruleset and forwards out the outbound endpoint.

| Dimension | Assessment |
|---|---|
| Complexity | Medium. Resolver plus two delegated subnets, plus a per-VNet DNS setting. |
| Cost | Resolver charges plus the spoke-to-hub flow through the NGFW. |
| Scalability | Medium. Still a per-spoke DNS server setting and a NIC refresh. |
| Team familiarity | Medium. Well documented, widely deployed. |
| Inspection | Best of the three. Spoke-to-hub 53 traffic hits the NGFW with the real client IP. |
| Exit readiness | Good. The resolver is NewCo-owned. Only the rule targets change at exit. |

**Pros**

- Private DNS zones resolve correctly, because the resolver answers from zones linked to its own VNet.
- The NGFW sees per-workload DNS behaviour, which is the strongest audit story.
- Single choke point for DNS policy.

**Cons**

- Carries the same per-spoke configuration burden as Option 1, which is the main thing we are trying to escape.
- Adds a hop and a hard dependency on inbound endpoint availability for every query in the estate.
- Changing the DNS server on an existing VNet does not take effect until NICs refresh, so migration waves need a restart window.

### Option 3: Private Resolver, ruleset linked to the spoke VNets **(DECISION)**

Microsoft's second reference pattern. Ruleset links are attached to each spoke. VMs stay on 168.63.129.16.

| Dimension | Assessment |
|---|---|
| Complexity | Medium. Resolver plus two delegated subnets, plus a ruleset link per spoke. |
| Cost | Resolver charges. No spoke-to-hub DNS flow, so slightly less firewall throughput. |
| Scalability | Best. The ruleset link is a Terraform resource in the spoke module. No VM restart, no DNS server setting. |
| Team familiarity | Medium. Newer pattern, less muscle memory on the team. |
| Inspection | Reduced. The NGFW sees the outbound endpoint as source, not the workload. Client attribution needs resolver query logs. |
| Exit readiness | Best. Change the rule target once, in one place, and the whole estate follows. |

**Pros**

- Private DNS zones and `privatelink` records resolve natively with no cross-tenant ask.
- No `.` catchall means public resolution never leaves the NewCo tenant. That removes an entire class of TSA dependency.
- Ruleset links work independently of peering, so a spoke does not need to be peered to the resolver VNet to use the rules. Useful for isolated or late-arriving landing zones.
- Divestiture exit is a rule target change, not an estate-wide reconfiguration.
- Fits the spoke Terraform module pattern owned by Iris cleanly. The link is one resource block per spoke.

**Cons**

- The NGFW sees only the outbound endpoint subnet as the source of forwarded queries, so per-workload attribution has to come from resolver query logging rather than firewall logs. This is the real trade and InfoSec has to accept it explicitly.
- The outbound endpoint subnet inherits the gateway-propagated route to on premises and will bypass the NGFW unless the UDR is applied. This is easy to miss and presents as working DNS with no inspection, which is worse than a clean failure.
- Ruleset link count grows with the spoke count and has a service limit that must be tracked against the migration wave plan.
- Rulesets cannot be linked across tenants, so if any ParentCo-tenant VNet ever needs these rules it will need its own resolver.

---

## Trade-off Analysis

**Option 1 fails on a hard technical constraint, not on preference.** The moment a workload points at a ParentCo resolver, Private Endpoint resolution in the NewCo tenant breaks, and the fix is a cross-tenant DNS path of a kind InfoSec has already declined once. Given the number of Private Endpoints in the target architecture, this is not a corner case. It is worth walking the room through Option 1 in full, because it is the intuitive answer and the diagram already exists, and then showing precisely where it lands.

**Options 2 and 3 differ on exactly one axis that matters: where client attribution comes from.** Option 2 buys firewall-level visibility of which workload asked for what, at the cost of a per-spoke DNS server setting and a restart window per migration wave. Option 3 gives that up and recovers it through resolver query logs, in exchange for a configuration model that scales without touching workloads at all.

Given that the spoke count is still growing and that migration waves are already the schedule bottleneck, the configuration burden is the more expensive of the two costs. Resolver query logging to Log Analytics closes most of the visibility gap, and the NGFW still sees and can block the forwarded flow itself, just without per-client granularity.

**The `.` catchall decision is separable and arguably more consequential than the pattern choice.** Sending everything to ParentCo resolvers is operationally simpler and matches what ParentCo does today, but it makes public name resolution for the entire NewCo Azure estate a ParentCo dependency that has to be unwound at divestiture under time pressure. Scoping rules to internal suffixes only costs a rule maintenance conversation and buys a much cleaner exit.

---

## Consequences

**What becomes easier**

- Adding a spoke. One Terraform resource, no VM restart, no DNS server setting.
- Divestiture cutover. Repointing DNS becomes a change to rule targets in one ruleset.
- Private Endpoint adoption. Private DNS zone resolution works without any on-premises cooperation.
- Public resolution resilience. A tunnel outage no longer takes out all name resolution, only internal suffixes.

**What becomes harder**

- Answering "which VM queried this domain" from firewall logs alone. That question now routes to resolver query logs, and somebody has to stand up that pipeline before go-live rather than after the first incident.
- Rule hygiene. Every new internal namespace needs a rule. A missed suffix presents as NXDOMAIN from Azure DNS, which looks like an application fault rather than a DNS gap.
- Troubleshooting which anycast node answered. The destination IP is identical everywhere, so `dig +nsid` or a CHAOS TXT query for `hostname.bind` belongs in the runbook now.

**What we will need to revisit**

- At ExpressRoute cutover, 172.16.53.53/32 moves from static local network gateway address space to a BGP-learned prefix. Confirm it arrives on exactly one connection to avoid asymmetric return through a different NGFW instance.
- At divestiture, whether NewCo stands up its own recursive service, uses Azure DNS Private Resolver alone, or leans on Zscaler for recursion.
- Interaction with ZIA DNS control. Confirm ZIA is not also intercepting 53 for these flows, so there is one authoritative answer on which system resolves what.
- Ruleset link count against the service limit as migration waves land.

---

## Action Items

1. [ ] Confirm with Hummin that the ADR is scoped to NewCo-tenant workloads only, and that ParentCo-side resolution is out of scope.
2. [ ] Get InfoSec to explicitly accept resolver query logs in place of per-client firewall attribution for DNS. Record the acceptance in this ADR.
3. [ ] Enumerate the internal DNS suffixes that require forwarding rules. Owner: NewCo Network with Glynsera on the ParentCo side.
4. [ ] Add 172.16.53.53/32 to the local network gateway address space and confirm reachability from the hub before building anything else.
5. [ ] Size and reserve the two delegated subnets in the hub IP plan, /28 or larger each, dedicated, no other resources.
6. [ ] Apply and test the UDR for 172.16.53.53/32 on the outbound endpoint subnet with the Cloud NGFW as next hop. Verify with a packet capture on the firewall, not just a successful lookup.
7. [ ] Add the ruleset link to the spoke Terraform module owned by Iris so it is applied by default on every new spoke.
8. [ ] Enable resolver query logging to Log Analytics and build the "who queried what" workbook before go-live.
9. [ ] Add anycast node identification (`dig +nsid`, CHAOS `hostname.bind`) to the DNS troubleshooting runbook.
10. [ ] Confirm ZIA is not intercepting port 53 for these flows.
11. [ ] Verify current Microsoft service limits for ruleset rules and virtual network links against the projected spoke count.
