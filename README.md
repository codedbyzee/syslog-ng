# IPDR Platform

> High-performance ISP IPDR collection platform built with **Syslog-NG**, **Kafka**, **ClickHouse**, and **Grafana**.

![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![Syslog-NG](https://img.shields.io/badge/Syslog--NG-4.3.1-0F766E?logo=linuxserver&logoColor=white)
![Kafka](https://img.shields.io/badge/Apache%20Kafka-3.9-231F20?logo=apachekafka&logoColor=white)
![ClickHouse](https://img.shields.io/badge/ClickHouse-24.12-FFCC01?logo=clickhouse&logoColor=black)
![Grafana](https://img.shields.io/badge/Grafana-11.4-F46800?logo=grafana&logoColor=white)
---

## Overview

The platform collects **IPDR (Internet Protocol Detail Records)** from network devices such as **MikroTik BRAS**, **vBNG**, and other syslog-enabled equipment.

Incoming syslog messages are streamed through Kafka, stored in ClickHouse, aggregated in real time, and visualized using Grafana.

Designed for:

- ISPs
- Broadband providers
- Network Operations Centers (NOC)
- Large-scale subscriber analytics

---

## Features

- High-performance syslog ingestion
- Native Kafka streaming
- ClickHouse real-time analytics
- Automatic aggregations using Materialized Views
- Pre-built Grafana dashboards
- Single-node Docker deployment
- Vendor-independent architecture
- Easily extensible for additional BRAS vendors

---

## Architecture & Data Flow

```
                        ┌─────────────────┐
                        │  MikroTik/vBNG  │  ← Provided by customer
                        └────────┬────────┘
                                 │ UDP :514
                                 ▼
    ┌─────────────────────────────────────────────────────────────┐
    │ ┌─────────────┐   ┌───────┐   ┌────────────┐   ┌──────────┐ │
    │ │  Syslog-NG  │ → │ Kafka │ → │ ClickHouse │ → │ Grafana  │ │
    │ └─────────────┘   └───────┘   └────────────┘   └──────────┘ │
    └─────────────────────────────────────────────────────────────┘
```

---

## Components

| Component | Purpose |
|------------|----------|
| **Syslog-NG** | Receives syslog and forwards to Kafka |
| **Kafka** | Buffers IPDR events |
| **ClickHouse** | Stores raw and aggregated data |
| **Grafana** | Dashboards and analytics |

---

## Project Structure

```text
.
├── clickhouse/
├── grafana/
├── kafka/
├── syslog-ng/
├── docker-compose.yml
├── .env
└── README.md
```

---

## Quick Start

```bash
docker compose up -d
```

Check running containers

```bash
docker ps
```

View logs

```bash
docker logs ipdr-syslog-ng
docker logs ipdr-kafka
docker logs ipdr-clickhouse
```

Stop

```bash
docker compose down
```

Remove everything

```bash
docker compose down -v
```

---

## Services

| Service | Port |
|----------|------|
| syslog UDP | 514 |
| syslog TCP | 514 |
| syslog TLS | 6514 |
| Grafana | 3000 |
| ClickHouse HTTP | 8123 |
| ClickHouse Native | 9000 |

Kafka remains internal to the Docker network.

---

## Environment Variables

| Variable | Default |
|----------|---------|
| CLICKHOUSE_DB | ipdr |
| CLICKHOUSE_USER | ipdr_user |
| CLICKHOUSE_PASSWORD | ipdr_secret |
| GRAFANA_ADMIN_USER | admin |
| GRAFANA_ADMIN_PASSWORD | admin |
| TZ | Asia/Karachi |

---

## ClickHouse Tables

### Raw

- kafka_ipdr
- ipdr_records

### Materialized Views

- kafka_ipdr_mv

### Aggregation Tables

- ipdr_hourly_traffic
- ipdr_daily_aggregation
- ipdr_subscriber_bandwidth
- ipdr_top_applications
- ipdr_top_destinations

---

## Grafana Dashboards

- Platform Overview
- Traffic Volume
- Bandwidth Usage
- Protocol Distribution
- Top Subscribers

---

## Troubleshooting

### Capability Warning

```
Error setting capabilities
```

Expected inside Docker and can be ignored.

---

### smart-multi-line.fsm Warning

```
smart-multi-line.fsm
```

Ubuntu's Syslog-NG package does not ship this optional file.

This warning does **not** affect IPDR collection.

---

## Roadmap

- Multi-BRAS support
- Multiple Kafka topics
- Multi-node ClickHouse cluster
- ClickStack support
- OpenTelemetry integration
- Alerting
- Authentication & RBAC
- High Availability deployment

---

## Technology Stack

- Ubuntu 24.04
- Syslog-NG 4.x
- Apache Kafka 3.9 (KRaft)
- ClickHouse 24.x
- Grafana 11.x
- Docker Compose

---

## License

Copyright © 2026 Terminus Technologies. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, modification, distribution, or use of this software, in whole or in part, is strictly prohibited without prior written permission from Terminus Technologies.