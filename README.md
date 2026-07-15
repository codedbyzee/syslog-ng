# IPDR Platform

> High-performance ISP IPDR collection platform built with **Syslog-NG → Kafka → ClickHouse → Grafana**.

![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![Syslog-NG](https://img.shields.io/badge/Syslog--NG-4.3.1-0F766E?logo=linuxserver&logoColor=white)
![Kafka](https://img.shields.io/badge/Apache%20Kafka-3.9-231F20?logo=apachekafka&logoColor=white)
![ClickHouse](https://img.shields.io/badge/ClickHouse-24.12-FFCC01?logo=clickhouse&logoColor=black)
![Grafana](https://img.shields.io/badge/Grafana-11.4-F46800?logo=grafana&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-64BC4B.svg?logo=wikibooks&logoColor=white)

---

## Overview

Collects **IPDR (Internet Protocol Detail Records)** from **vBNG** (Huawei NAT) and **MikroTik** routers. Syslog messages flow through Kafka, are stored in ClickHouse, aggregated in real-time, and visualized in Grafana.

Designed for ISPs, broadband providers, and NOCs.

---

## Data Flow

```
                                    ┌─────────────────────┐
                                    │  MikroTik / vBNG    │
                                    ├─────────────────────┤
                                    │  MikroTik / vBNG    │
                                    ├─────────────────────┤
                                    │  MikroTik / vBNG    │
                                    └──────────┬──────────┘
                                               │ UDP 514 / TLS 6514
                                               ▼
             ┌───────────────────────────────────────────────────────────────────┐
             │ ┌─────────────┐   ┌───────────┐   ┌────────────┐   ┌────────────┐ │
             │ │  Syslog-NG  │ → │   Kafka   │ → │ ClickHouse │ → │   Grafana  │ │
             │ │  (no-parse) │   │  (buffer) │   │ (MV parser)│   │(dashboards)│ │
             │ └─────────────┘   └───────────┘   └────────────┘   └────────────┘ │
             └───────────────────────────────────────────────────────────────────┘
```

### Supported Log Formats

| Source | Format | Example Fields |
|---|---|---|
| **vBNG** | RFC 5424 syslog with `[nsess ...]` SD | `USERNAME`, `ISADDR`, `IDADDR`, `ISPORT`, `IDPORT`, `PROTO` |
| **MikroTik** | Connection tracking text | `pppoe-user`, `src_ip:port`, `dst_ip:port`, `NAT ip:port` |

---

## Project Structure

```
syslog/
├── .env                       # Environment variables (ports, passwords)
├── docker-compose.yml         # Production stack
├── clickhouse/
│   ├── config.d/config.xml    # Server config (listen_host, memory)
│   └── init/01-create-tables.sh  # Schema + MVs
├── grafana/
│   ├── dashboards/            # Pre-built dashboards
│   └── provisioning/          # Datasource + dashboard auto-config
├── kafka/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── scripts/
├── simulators/                # Test log generators (separate stack)
│   ├── docker-compose.yml
│   ├── vbng/                  # Sends vBNG-format syslog
│   └── mikrotik/              # Sends MikroTik-format syslog
├── syslog-ng/
│   ├── Dockerfile
│   └── config/
│       ├── syslog-ng.conf     # Main config (UDP 514 + TLS 6514)
│       └── tls/               # Self-signed TLS certs (replace for prod)
└── .env
```

---

## Quick Start

```bash
# 1. Start production stack
docker compose up -d

# 2. (Optional) Start simulators for testing
docker compose -f simulators/docker-compose.yml up -d

# 3. Check data flowing
docker compose exec clickhouse clickhouse-client --user ipdr_user --password ipdr_secret \
  --query "SELECT subscriber_id, source_ip, destination_ip, protocol FROM ipdr.ipdr_records ORDER BY timestamp DESC LIMIT 5"
```

---

## Configuration

### Environment (`.env`)

| Variable | Default | Description |
|---|---|---|
| `SYSLOG_UDP_PORT` | `514` | UDP syslog listen port |
| `SYSLOG_TCP_PORT` | `514` | TCP syslog listen port |
| `SYSLOG_TLS_PORT` | `6514` | TLS syslog listen port |
| `CLICKHOUSE_DB` | `ipdr` | ClickHouse database name |
| `CLICKHOUSE_USER` | `ipdr_user` | ClickHouse user |
| `CLICKHOUSE_PASSWORD` | `ipdr_secret` | **Change for production** |
| `GRAFANA_PORT` | `3000` | Grafana web UI port |
| `GRAFANA_ADMIN_PASSWORD` | `admin1234` | **Change for production** |

---

## Ports

| Port | Service | Protocol | Purpose |
|---|---|---|---|
| `514` | syslog-ng | UDP/TCP | Legacy syslog |
| `6514` | syslog-ng | TCP TLS | Secure syslog |
| `8123` | ClickHouse | TCP | HTTP API |
| `9000` | ClickHouse | TCP | Native protocol |
| `3000` | Grafana | TCP | Web UI |
| `9092` | Kafka | TCP | Internal only |

---

## Simulators (Testing)

Send realistic test data without real devices:

```bash
cd simulators
docker compose up -d
```

This starts two containers that generate random vBNG and MikroTik syslog messages and send them to the production stack.

To stop:
```bash
docker compose -f simulators/docker-compose.yml down
```

---

## Production Deployment

```bash
# 1. Replace TLS certs with real domain certs
cp fullchain.pem syslog-ng/config/tls/server.crt
cp privkey.pem  syslog-ng/config/tls/server.key

# 2. Change passwords in .env
# 3. Deploy
docker compose up -d
```

---

## Architecture Details

### syslog-ng
- `flags(no-parse)` preserves raw RFC 5424 structured data
- UDP (514) + TLS (6514) listeners
- Forwards raw messages to Kafka topic `ipdr-events`

### ClickHouse
- `kafka_ipdr` — Kafka engine table consuming `ipdr-events`
- `kafka_ipdr_mv` — Materialized View parsing 3 formats:
  - JSON (backward compatible)
  - vBNG `KEY="VALUE"` pairs
  - MikroTik `in:<user>` + `IP:port` patterns
- Aggregation MVs: daily, hourly, top destinations, top apps, subscriber bandwidth

### Grafana
- Auto-provisioned ClickHouse datasource
- 5 pre-built dashboards: overview, bandwidth, protocol distribution, subscriber ranking, traffic volume

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

This project is licensed under the [MIT License](LICENSE).