# Home IoT DNS Analysis

## Overview
A comprehensive analysis of DNS query logs from 21 IoT devices on a home network 
over an 8-week period (March 1 – April 26, 2026). Using Python, SQL, and Tableau, 
this project identifies anomalous device behavior through statistical analysis and 
network traffic pattern recognition.

## Hypothesis
Passive DNS logs from a residential IoT network can reveal undisclosed device behavior 
and detectable anomalies such as security threats and service outages, allowing for the 
development of a resource-efficient detection system.

## Tools & Technologies
- **PostgreSQL** — data storage and querying
- **Python** (Pandas, Seaborn, Plotly, Folium, SciPy) — analysis and visualization
- **Tableau** — interactive dashboard
- **MaxMind GeoLite2** — IP geolocation

## Infrastructure
All data collection infrastructure was self-hosted and configured from scratch:
- **Proxmox** host running containerized services
- **Pi-hole** — DNS/DHCP server and primary data source, configured to log all 
  queries to PostgreSQL hourly with gap-tolerant ingestion
- **PostgreSQL** — database server storing and serving all DNS log data
- **Device Identification** — all 21 IoT devices manually identified and labeled 
  through network investigation

This project covers the full pipeline from raw DNS log collection through analysis 
and visualization — not just the analytical layer.

## Key Findings
- **3D Printer** — 1,942 queries to a single unknown domain (api.voxelshare.com) 
  in a single afternoon, with no user-initiated activity. DNS timestamps reveal a 
  clear behavioral progression from initial handshake attempts to a full aggressive 
  retry loop. Most significant finding in the dataset.
- **Smart Plug** — Averaging 718 queries/hour (~17,232/day) after reconnecting, 
  up from a previous baseline of 2–10 queries/day. Root cause: Belkin discontinued 
  Wemo cloud services on January 31, 2026. Device appeared fully functional without 
  DNS monitoring.
- **Digital Photo Frame** — High anomaly count explained as a baseline sensitivity 
  artifact, not true anomalous behavior. Demonstrates the importance of context in 
  anomaly detection.

## Methodology
- Z-score analysis on hourly query totals per device to flag statistical anomalies
- Chi-square testing to confirm non-uniform query distribution
- SQL session analysis to reconstruct device retry behavior from raw timestamps
- IP geolocation to map network traffic geographically

## Files
- `DNS Analysis.ipynb` — full analysis notebook
- `DNS Analysis.sql` — investigative SQL queries and findings
- CSV export of the IoT_data view available on request.

- ## Visualizations
[View the Tableau Dashboard here](https://public.tableau.com/app/profile/jeff.kimbrel/viz/DNSAnalysis_17784659035450/Sheet9) *(Story/Dashboard work in progress)*


## Interactive Notebook
[View with interactive maps on nbviewer](Link will be added soon)
