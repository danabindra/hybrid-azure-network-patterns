## Network Flows (Azure NW Strategy)

<p align="center">
  <img src="png/1_onprem_er.png" alt="On-Prem → Azure Hub via ER" width="100%">
</p>

<p align="center">
  <img src="diagrams/png/2_hub_hub_transit.png" alt="Hub↔Hub Inter-Region Transit (FE/BE lanes)" width="100%">
</p>

<p align="center">
  <img src="diagrams/png/3_spoke_hub_spoke.png" alt="Spoke→Hub→Spoke (no direct peering)" width="100%">
</p>

<p align="center">
  <img src="diagrams/png/4_internet_egress_fxf.png" alt="Internet Egress via FXF Hub" width="100%">
</p>

<p align="center">
  <img src="diagrams/png/5_remote_access.png" alt="Remote Access (VPN/ZTNA into Hub)" width="100%">
</p>

<p align="center">
  <img src="diagrams/png/6_s2s_backup.png" alt="Site-to-Site VPN (backup path)" width="100%">
</p>

<p align="center">
  <img src="diagrams/png/7_internet_ingress.png" alt="Internet Ingress traffic (WAF → NVA → Spokes)" width="100%">
</p>





