# IPDR Logging Platform

A production-ready Docker Compose-based platform for collecting, streaming, storing, and visualizing IPDR (IP Detail Record) syslog data.

## Architecture

```
┌─────────────┐     ┌──────────┐     ┌───────────────┐     ┌────────────┐
│  Network    │────▶│ syslog-ng│────▶│    Kafka      │────▶│  Consumer  │
│  Devices    │     │ (514)    │     │  (KRaft)      │     │  (Node.js) │
└─────────────┘     └──────────┘     │ ipdr-events   │     └──────┬─────┘
                                     └───────────────┘            │
                                                                    ▼
                                                              ┌────────────┐
                                                              │ ClickHouse │
                                                              │  (OLAP)    │
                                                              └──────┬─────┘
                                                                     │
                                                                     ▼
                                                               ┌─────────┐
                                                               │ Grafana │
                                                               │ (:3000) │
                                                               └─────────┘
```

### Data Flow

1. **Network devices** send IPDR syslog messages (UDP 514 / TCP 514 / TLS 6514)
2. **syslog-ng** parses structured data and publishes to Kafka topic `ipdr-events`
3. **Kafka** (KRaft mode, no Zookeeper) buffers messages for reliable delivery
4. **kafka-consumer** (Node.js) reads from `ipdr-events`, parses JSON, and batch-inserts into ClickHouse
5. **ClickHouse** stores IPDR records in monthly-partitioned MergeTree tables with 90-day TTL
6. **Grafana** queries ClickHouse for real-time dashboards and alerting

## Services

| Service          | Image                                    | Port(s)              | Purpose                              |
|------------------|------------------------------------------|----------------------|--------------------------------------|
| syslog-ng        | `lscr.io/linuxserver/syslog-ng:4.10.2`   | 514 (UDP/TCP), 6514  | Syslog collection & forwarding       |
| Apache Kafka   | `apache/kafka:3.9.0` (custom build)       | 9092, 9093           | Message broker (KRaft mode, no ZooKeeper) |
| kafka-consumer   | `custom (Node.js 20)`                    | 8080 (health)        | Kafka → ClickHouse batch consumer    |
| clickhouse-migrate | `clickhouse/clickhouse-server:24.12`   | —                    | Schema migration runner (one-shot)   |
| ClickHouse       | `clickhouse/clickhouse-server:24.12`     | 8123 (HTTP), 9000    | Columnar OLAP storage                |
| Grafana          | `grafana/grafana:11.4`                   | 3000                 | Dashboards & alerting                |

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) ≥ 24.0
- [Docker Compose](https://docs.docker.com/compose/install/) ≥ 2.20
- Minimum 4 GB RAM allocated to Docker

## Quick Start

```bash
# 1. Clone and enter the platform directory
cd ipdr-platform

# 2. Configure environment (optional — defaults work for local dev)
cp .env.example .env
# Edit .env to customize ports, passwords, etc.

# 3. Start all services
docker compose up -d

# 4. Check service health
docker compose ps
./scripts/check-health.sh

# 5. Follow logs
docker compose logs -f
```

## Access Points

| Service        | URL                                      | Credentials            |
|----------------|------------------------------------------|------------------------|
| Grafana        | http://localhost:3000                    | `admin` / `admin`      |
| ClickHouse     | `clickhouse-client --host localhost`     | `default` / (none)     |
| Kafka          | `localhost:9092`                         | —                      |
| Kafka Consumer | http://localhost:8080/health             | —                      |

## Dashboards

Five Grafana dashboards are auto-provisioned on startup:

| Dashboard | UID | Panels | Description |
|---|---|---|---|
| **IPDR Platform Overview** | `ipdr-overview` | 9 | Main landing — logs/sec, bandwidth, active subscribers, top apps & subs |
| **IPDR Traffic Volume** | `ipdr-traffic-volume` | 9 | Sessions/sec, bandwidth throughput, hourly pattern, heatmap, 30d trend |
| **IPDR Subscriber Ranking** | `ipdr-subscriber-ranking` | 9 | Top 20 subs by bandwidth, error subscribers, growth, usage distribution |
| **IPDR Bandwidth Usage** | `ipdr-bandwidth-usage` | 12 | Bandwidth by service/APN/RAT, daily trend, throughput efficiency |
| **IPDR Protocol Distribution** | `ipdr-protocol-distribution` | 12 | Protocol pie/trend, destination IPs, app matrix, port distribution |

All dashboards use the auto-provisioned **ClickHouse** datasource and query the analytics materialized views (`ipdr_hourly_traffic`, `ipdr_top_destinations`, `ipdr_top_applications`, `ipdr_subscriber_bandwidth`) for sub-second performance.

## Configuration

### Environment Variables

All configuration is managed via `.env` file. Key variables:

| Variable                            | Default             | Description                                |
|-------------------------------------|---------------------|--------------------------------------------|
| `SYSLOG_UDP_PORT`                   | `514`               | UDP syslog listen port                     |
| `SYSLOG_TCP_PORT`                   | `514`               | TCP syslog listen port                     |
| `SYSLOG_TLS_PORT`                   | `6514`              | TLS syslog listen port                     |
| `KAFKA_PORT`                        | `9092`              | Kafka client port                          |
| `KAFKA_HEAP_OPTS`                   | `-Xmx2g -Xms2g`     | Kafka JVM heap allocation                  |
| `KAFKA_NUM_PARTITIONS`              | `8`                 | Default partition count                    |
| `KAFKA_LOG_RETENTION_HOURS`         | `168`               | Kafka log retention (7 days)               |
| `KAFKA_LOG_RETENTION_BYTES`         | `10737418240`       | Max bytes per partition (10 GB)            |
| `KAFKA_LOG_SEGMENT_BYTES`           | `536870912`         | Log segment size (512 MB)                  |
| `KAFKA_COMPRESSION_TYPE`            | `snappy`            | Global compression algorithm               |
| `KAFKA_MESSAGE_MAX_BYTES`           | `10485760`          | Max message size (10 MB)                   |
| `KAFKA_NUM_NETWORK_THREADS`         | `6`                 | Network thread pool size                   |
| `KAFKA_NUM_IO_THREADS`              | `10`                | I/O thread pool size                       |
| `KAFKA_MIN_INSYNC_REPLICAS`         | `1`                 | Minimum in-sync replicas                   |
| `KAFKA_TOPIC`                       | `ipdr-events`       | Primary IPDR topic name                    |
| `KAFKA_IPDR_EVENTS_PARTITIONS`      | `8`                 | Partitions for ipdr-events topic           |
| `KAFKA_SECURITY_EVENTS_PARTITIONS`  | `8`                 | Partitions for security-events topic       |
| `CLICKHOUSE_DB`                     | `ipdr`              | ClickHouse database name                   |
| `CLICKHOUSE_USER`                   | `default`           | ClickHouse admin user                      |
| `CLICKHOUSE_BATCH_SIZE`             | `10000`             | ClickHouse batch insert size               |
| `CLICKHOUSE_BATCH_INTERVAL_MS`      | `5000`              | Max wait before flushing a partial batch   |
| `KAFKA_CONSUMER_HEALTH_PORT`        | `8080`              | Consumer health check HTTP port            |
| `GRAFANA_PORT`                      | `3000`              | Grafana web UI port                        |
| `GRAFANA_ADMIN_PASSWORD`            | `admin`             | Grafana admin password                     |

### TLS for syslog-ng

To enable TLS on port 6514, place your certificate and key:

```bash
mkdir -p syslog-ng/config/tls
cp your-server.crt syslog-ng/config/tls/server.crt
cp your-server.key syslog-ng/config/tls/server.key
```

## Apache Kafka (KRaft Mode)

Kafka runs in **KRaft mode** (no ZooKeeper) using the official `apache/kafka:3.9.0` image. A single node acts as both broker and controller.

### Data Flow

```
Producer (syslog-ng) ──port 9092──▶ Kafka ──port 9093──▶ Controller (internal)
                                        │
                                        ▼
                                   /var/lib/kafka/data
                                   (persistent volume)
```

### Environment Variable Reference

Each `KAFKA_*` environment variable maps directly to a Kafka configuration property. The official image entrypoint strips the `KAFKA_` prefix, lowercases the name, and replaces `_` with `.` to generate the `server.properties` file.

| Env Variable | Kafka Property | Value | Explanation |
|---|---|---|---|
| `KAFKA_KRAFT_CLUSTER_ID` | *(special)* | `_ZZdMiVcTJuBQCdVFWcsqg` | Unique ID for the KRaft metadata log partition. **Required** for KRaft mode. Generated via `kafka-storage.sh random-uuid`. Must persist across restarts. |
| `KAFKA_NODE_ID` | `node.id` | `1` | Unique identifier for this broker in the cluster. |
| `KAFKA_PROCESS_ROLES` | `process.roles` | `broker,controller` | Both roles run in the same JVM. The controller manages the metadata log; the broker handles client requests. |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | `controller.quorum.voters` | `1@kafka:9093` | Defines the set of controller nodes for the KRaft quorum. Format: `<nodeId>@<host>:<controllerPort>`. Single node = one voter. |
| `KAFKA_LISTENERS` | `listeners` | `INTERNAL://:9092,EXTERNAL://:9094,CONTROLLER://:9093` | Comma-separated listener URIs. `INTERNAL` for Docker network, `EXTERNAL` for host access, `CONTROLLER` for KRaft. |
| `KAFKA_ADVERTISED_LISTENERS` | `advertised.listeners` | `INTERNAL://kafka:9092,EXTERNAL://localhost:9094` | Addresses published to clients. Internal services use `kafka:9092`; external tools use `localhost:9094`. |
| `KAFKA_LISTENER_SECURITY_PROTOCOL_MAP` | `listener.security.protocol.map` | `INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT` | Maps listener names to security protocols. All `PLAINTEXT` (no TLS in dev). |
| `KAFKA_CONTROLLER_LISTENER_NAMES` | `controller.listener.names` | `CONTROLLER` | Tells KRaft which listener to use for controller traffic. |
| `KAFKA_INTER_BROKER_LISTENER_NAME` | `inter.broker.listener.name` | `INTERNAL` | Listener used for inter-broker communication. |
| `KAFKA_NUM_PARTITIONS` | `num.partitions` | `8` | Default partition count for auto-created topics. |
| `KAFKA_DEFAULT_REPLICATION_FACTOR` | `default.replication.factor` | `1` | Must be `1` for a single-node cluster (cannot replicate to itself). |
| `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR` | `offsets.topic.replication.factor` | `1` | Replication factor for the internal `__consumer_offsets` topic. |
| `KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR` | `transaction.state.log.replication.factor` | `1` | Replication factor for the transaction state topic. |
| `KAFKA_AUTO_CREATE_TOPICS_ENABLE` | `auto.create.topics.enable` | `true` | Allows producers/consumers to create topics on the fly. Our init script also creates topics with specific configs. |
| `KAFKA_LOG_RETENTION_HOURS` | `log.retention.hours` | `168` | How long to keep log segments before deletion (168h = 7 days). |
| `KAFKA_LOG_RETENTION_BYTES` | `log.retention.bytes` | `10737418240` | Maximum size per partition before old segments are deleted (10 GB). |
| `KAFKA_LOG_SEGMENT_BYTES` | `log.segment.bytes` | `536870912` | Max size of a single log segment file (512 MB). Larger = less frequent rolling. |
| `KAFKA_LOG_ROLL_MS` | `log.roll.ms` | `86400000` | Max time before a log segment is closed and a new one starts (24h). |
| `KAFKA_LOG_CLEANUP_POLICY` | `log.cleanup.policy` | `delete` | Deletes old segments based on retention constraints. Alternative is `compact` for key-compacted topics. |
| `KAFKA_COMPRESSION_TYPE` | `compression.type` | `snappy` | Default compression for producers that don't specify their own. Snappy balances CPU ↔ compression ratio. |
| `KAFKA_MESSAGE_MAX_BYTES` | `message.max.bytes` | `10485760` | Maximum size of a single Kafka message (10 MB). |
| `KAFKA_NUM_NETWORK_THREADS` | `num.network.threads` | `6` | Threads handling network requests from clients. |
| `KAFKA_NUM_IO_THREADS` | `num.io.threads` | `10` | Threads handling disk I/O operations (reads/writes). |
| `KAFKA_MIN_INSYNC_REPLICAS` | `min.insync.replicas` | `1` | Minimum in-sync replicas required for acks=all. Must be ≤ replication factor. |
| `KAFKA_HEAP_OPTS` | *(JVM)* | `-Xmx2g -Xms2g` | Passed directly to the Kafka JVM. Set heap min/max to same value to avoid GC resize pauses. |

### Verify Kafka is Running

```bash
# Check container status
docker compose ps kafka

# Check Kafka logs for KRaft initialization
docker compose logs kafka | grep -E "(KRaft|metadata|controller|started|ready)"

# List Kafka topics
docker exec ipdr-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Describe a specific topic
docker exec ipdr-kafka kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic ipdr-events

# Check Kafka broker status via the built-in API
docker exec ipdr-kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | head -20

# Check controller quorum status
docker exec ipdr-kafka kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status
```

### Create a Test Topic

```bash
# Manual creation (topics are auto-created by the init script on startup)
docker exec ipdr-kafka kafka-topics.sh --bootstrap-server localhost:9092 \
    --create \
    --topic test-topic \
    --partitions 3 \
    --replication-factor 1 \
    --config retention.ms=3600000 \
    --config compression.type=snappy

# Verify the topic was created
docker exec ipdr-kafka kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic test-topic
```

### Produce and Consume Test Messages

```bash
# Terminal 1: Start a console consumer
docker exec -it ipdr-kafka kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic test-topic \
    --from-beginning \
    --group test-group

# Terminal 2: Produce messages
docker exec -it ipdr-kafka kafka-console-producer.sh \
    --bootstrap-server localhost:9092 \
    --topic test-topic \
    --property "parse.key=true" \
    --property "key.separator=:"

# Type messages in the producer terminal:
# key1:Hello IPDR platform
# key2:This is a test message
# key3:{"event":"test","timestamp":"2026-07-13T12:00:00Z"}
# (Ctrl+D to exit)

# Alternative: produce without key
docker exec -it ipdr-kafka kafka-console-producer.sh \
    --bootstrap-server localhost:9092 \
    --topic test-topic

# Measure producer throughput
docker exec ipdr-kafka kafka-producer-perf-test.sh \
    --topic test-topic \
    --num-records 100000 \
    --record-size 1024 \
    --throughput 50000 \
    --producer-props bootstrap.servers=localhost:9092 compression.type=snappy
```

### Common Troubleshooting

```bash
# View broker metadata
docker exec ipdr-kafka kafka-metadata-shell.sh \
    --snapshot /var/lib/kafka/data/__cluster_metadata-0/*.log

# Reset a consumer group offset
docker exec ipdr-kafka kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --group test-group \
    --topic test-topic \
    --reset-offsets --to-earliest --execute

# Describe consumer group status
docker exec ipdr-kafka kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --group test-group \
    --describe
```

## Production Deployment

### Resource Limits

Set Docker resource limits via environment or `docker-compose.override.yml`:

```yaml
services:
  clickhouse:
    deploy:
      resources:
        limits:
          memory: 8G
        reservations:
          memory: 4G
```

### High Availability

For production HA deployments:

- **Kafka**: Add multiple KRaft nodes by increasing `KAFKA_NODE_ID` and updating `KAFKA_CONTROLLER_QUORUM_VOTERS`
- **ClickHouse**: Configure clustered replication with multiple nodes
- **syslog-ng**: Run multiple instances behind a load balancer
- **Grafana**: Enable database-backed HA mode

### Security Considerations

1. Change all default passwords in `.env` before production use
2. Restrict `listen_host` in ClickHouse config to specific subnets
3. Enable TLS for syslog-ng (port 6514)
4. Use `GRAFANA_ANONYMOUS=false` in production
5. Use secrets management (Docker secrets) for sensitive credentials
6. Configure Docker's `ulimit` settings for Kafka (nofile ≥ 100000)

## Maintenance

### Backups

```bash
# ClickHouse
docker exec ipdr-clickhouse clickhouse-client --query "BACKUP TABLE ipdr.ipdr_logs TO 'backup.zip'"

# Grafana
docker exec ipdr-grafana tar czf /tmp/grafana-backup.tar.gz /var/lib/grafana
docker cp ipdr-grafana:/tmp/grafana-backup.tar.gz .
```

### Topics

| Topic             | Partitions | Retention | Compression | Purpose                        |
|-------------------|------------|-----------|-------------|--------------------------------|
| `ipdr-events`     | 8          | 7 days    | snappy      | Primary IPDR log stream        |
| `security-events` | 8          | 30 days   | snappy      | Security events for compliance |
| `system-events`   | 8          | 7 days    | snappy      | Platform health & monitoring   |

## ClickHouse Schema

Schema migrations run automatically via the `clickhouse-migrate` service on first startup. Below is the logical schema.

### `ipdr.ipdr_records` — Raw IPDR Fact Table

| Column            | Type                    | Description                              |
|-------------------|-------------------------|------------------------------------------|
| `timestamp`       | `DateTime`              | Event timestamp                          |
| `collector_id`    | `LowCardinality(String)`| syslog-ng collector source               |
| `subscriber_id`   | `String`                | Primary subscriber ID (MSISDN / account) |
| `subscriber_ip`   | `IPv6`                  | Subscriber IP at session time            |
| `imsi`            | `String`                | International Mobile Subscriber Identity |
| `imei`            | `String`                | International Mobile Equipment Identity  |
| `msisdn`          | `String`                | Mobile Subscriber ISDN number            |
| `source_ip`       | `IPv6`                  | Source address                           |
| `destination_ip`  | `IPv6`                  | Destination address                      |
| `source_port`     | `UInt16`                | Source port                              |
| `destination_port`| `UInt16`                | Destination port                         |
| `protocol`        | `LowCardinality(String)`| TCP / UDP / ICMP / ...                   |
| `service_type`    | `LowCardinality(String)`| Service classification                   |
| `apn`             | `LowCardinality(String)`| Access Point Name                        |
| `rat_type`        | `LowCardinality(String)`| Radio Access Technology (4G, 5G, etc.)   |
| `cell_id`         | `String`                | Cell tower ID                            |
| `bytes_in`        | `UInt64`                | Downstream bytes                         |
| `bytes_out`       | `UInt64`                | Upstream bytes                           |
| `bytes_total`     | `UInt64` *(materialized)* | `bytes_in + bytes_out`                |
| `packets_in`      | `UInt64`                | Downstream packets                       |
| `packets_out`     | `UInt64`                | Upstream packets                         |
| `duration_seconds`| `UInt32`                | Session duration                         |
| `status`          | `LowCardinality(String)`| Session result (success/failure/...)     |
| `cause_code`      | `String`                | Termination cause code                   |
| `charging_id`     | `String`                | Charging correlation ID                  |
| `raw_message`     | `String`                | Original syslog payload for debugging    |
| `parsed_at`       | `DateTime` *(materialized)* | Insert time                          |

**Design decisions:**

| Feature            | Setting                                      |
|--------------------|----------------------------------------------|
| Engine             | `MergeTree`                                  |
| Partition          | `toYYYYMM(timestamp)` — monthly              |
| Order key          | `(subscriber_id, timestamp)`                 |
| TTL                | `timestamp + INTERVAL 90 DAY`                |
| Indexes            | 8 skip indexes (see migration `002`)         |
| Compression        | ZSTD(3) — configured globally               |

### `ipdr.ipdr_daily_aggregation` — Bandwidth Reports (Existing)

Pre-aggregated via materialized view. Query in milliseconds vs scanning billions of raw rows.

- **Engine:** `SummingMergeTree` — duplicate rows merge automatically
- **Partition:** `toYYYYMM(day)` — monthly
- **Order:** `(day, subscriber_id, service_type, apn, rat_type)`
- **TTL:** `day + INTERVAL 365 DAY`
- **Metrics per (day, subscriber):** session count, bytes in/out, packets, avg/max/total duration, error count, unique destinations, unique cells

### Analytics Views (Migration `005`)

| View | Purpose | TTL | Order Key |
|---|---|---|---|
| `ipdr_hourly_traffic` | Traffic volume by hour, service & protocol | 90 days | `(hour, service_type, protocol, rat_type)` |
| `ipdr_top_destinations` | Top destination IPs by traffic volume | 90 days | `(day, destination_ip, service_type, protocol)` |
| `ipdr_top_applications` | Application bandwidth breakdown | 180 days | `(day, service_type, protocol, apn)` |
| `ipdr_subscriber_bandwidth` | Per-subscriber daily bandwidth usage | 365 days | `(day, subscriber_id, service_type, rat_type)` |

**`ipdr_hourly_traffic`** — hourly rollup of sessions, bytes, packets, unique subscribers, and destinations.

```sql
-- Peak hours analysis
SELECT toHour(hour) AS h, sum(session_count) AS sessions, sum(total_bytes) AS bytes
FROM ipdr.ipdr_hourly_traffic
WHERE hour >= now() - INTERVAL 7 DAY
GROUP BY h ORDER BY bytes DESC;
```

**`ipdr_top_destinations`** — which destination IPs receive the most traffic, per day.

```sql
-- Top 10 destinations today
SELECT destination_ip, service_type, sum(total_bytes) AS bytes, sum(session_count) AS sessions
FROM ipdr.ipdr_top_destinations
WHERE day = today()
GROUP BY destination_ip, service_type
ORDER BY bytes DESC LIMIT 10;
```

**`ipdr_top_applications`** — bandwidth per application (service_type + protocol) for capacity planning.

```sql
-- Application ranking this month
SELECT service_type, protocol,
       sum(total_bytes) / 1073741824 AS bandwidth_gb,
       sum(session_count) AS sessions,
       sum(unique_subscribers) AS users
FROM ipdr.ipdr_top_applications
WHERE day >= toStartOfMonth(today())
GROUP BY service_type, protocol
ORDER BY bandwidth_gb DESC;
```

**`ipdr_subscriber_bandwidth`** — per-subscriber daily usage for billing and throttle decisions.

```sql
-- Top 10 bandwidth consumers yesterday
SELECT subscriber_id,
       total_bytes / 1073741824 AS usage_gb,
       session_count,
       error_count
FROM ipdr.ipdr_subscriber_bandwidth
WHERE day = yesterday()
ORDER BY total_bytes DESC LIMIT 10;

-- Monthly usage for a specific subscriber
SELECT sum(total_bytes) / 1073741824 AS monthly_gb,
       sum(session_count) AS sessions,
       sum(error_count) AS errors
FROM ipdr.ipdr_subscriber_bandwidth
WHERE subscriber_id = 'SUBSCRIBER_ID_HERE'
  AND day >= toStartOfMonth(today());

### `ipdr.ipdr_events_kafka` — Kafka Consumer

Two-table approach: Kafka engine table (virtual stream) + materialized view that transforms JSON → columns → writes to `ipdr_records`.

- **Topic:** `ipdr-events` (from syslog-ng)
- **Consumers:** 4 parallel consumers
- **Format:** `JSONAsString` — parses nested `.ipdr.*` fields via `JSONExtract*` functions
- **Group:** `clickhouse-ipdr-consumer`

### Running Migrations Manually

```bash
# Migrations run automatically via docker-compose on first start.
# To re-run manually:
docker compose run --rm clickhouse-migrate

# Check status of applied migrations:
docker compose run --rm -e CLICKHOUSE_HOST=clickhouse clickhouse-migrate \
    /bin/bash -c "cd /migrations && bash run.sh --status"

# Apply a specific migration file:
docker exec ipdr-clickhouse clickhouse-client --multiquery < clickhouse/migrations/002_create_ipdr_records.sql
```

### Log Rotation

- **Kafka**: retention configured per-topic via `retention.ms` and `retention.bytes` (default 7 days, 10 GB per partition)
- **syslog-ng**: uses Docker log driver (configure `log-opts max-size=10m max-file=3` in compose)
- **ClickHouse**: TTL policies should be defined on the IPDR table (merge tree TTL)

### Monitoring

```bash
# Service health
./scripts/check-health.sh

# Kafka topic details — all topics
docker exec ipdr-kafka kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic ipdr-events
docker exec ipdr-kafka kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic security-events

# Kafka producer performance test
docker exec ipdr-kafka kafka-producer-perf-test.sh \
    --topic ipdr-events \
    --num-records 100000 \
    --record-size 1024 \
    --throughput 50000 \
    --producer-props bootstrap.servers=localhost:9092 compression.type=snappy

# ClickHouse system health
docker exec ipdr-clickhouse clickhouse-client --query "SELECT * FROM system.metrics"
```

### Common Queries

```sql
-- Subscriber bandwidth usage (last 24h)
SELECT subscriber_id,
       sum(bytes_in) AS mb_in,
       sum(bytes_out) AS mb_out,
       sum(bytes_total) AS total_mb
FROM ipdr.ipdr_records
WHERE timestamp >= now() - INTERVAL 1 DAY
  AND subscriber_id = 'SUBSCRIBER_ID_HERE'
GROUP BY subscriber_id;

-- Top talkers (today)
SELECT source_ip,
       destination_ip,
       sum(bytes_total) AS total_bytes,
       count() AS sessions
FROM ipdr.ipdr_records
WHERE timestamp >= today()
GROUP BY source_ip, destination_ip
ORDER BY total_bytes DESC
LIMIT 20;

-- Daily bandwidth report
SELECT day,
       subscriber_id,
       total_bytes_in / 1048576 AS mb_in,
       total_bytes_out / 1048576 AS mb_out,
       session_count,
       error_count
FROM ipdr.ipdr_daily_aggregation
WHERE day >= today() - 7
ORDER BY day DESC, mb_total DESC;

-- Hourly traffic pattern (last 24h)
SELECT toHour(hour) AS h,
       sum(session_count) AS sessions,
       sum(total_bytes) / 1048576 AS mb
FROM ipdr.ipdr_hourly_traffic
WHERE hour >= now() - INTERVAL 1 DAY
GROUP BY h ORDER BY h;

-- Top destinations this week
SELECT destination_ip,
       sum(total_bytes) / 1073741824 AS gb,
       sum(session_count) AS sessions,
       sum(unique_subscribers) AS users
FROM ipdr.ipdr_top_destinations
WHERE day >= today() - 7
GROUP BY destination_ip
ORDER BY gb DESC LIMIT 20;

-- Application ranking
SELECT service_type, protocol,
       sum(total_bytes) / 1073741824 AS gb
FROM ipdr.ipdr_top_applications
WHERE day >= toStartOfMonth(today())
GROUP BY service_type, protocol
ORDER BY gb DESC;

-- Heavy subscriber alert (top 1% bandwidth users today)
SELECT subscriber_id,
       total_bytes / 1073741824 AS gb
FROM ipdr.ipdr_subscriber_bandwidth
WHERE day = today()
ORDER BY gb DESC
LIMIT 10;

-- Protocol distribution
SELECT protocol,
       count() AS sessions,
       sum(bytes_total) AS total_bytes
FROM ipdr.ipdr_records
WHERE timestamp >= now() - INTERVAL 1 DAY
GROUP BY protocol
ORDER BY total_bytes DESC;

-- Active subscribers (last 5 min)
SELECT uniqExact(subscriber_id) AS active_subscribers
FROM ipdr.ipdr_records
WHERE timestamp >= now() - INTERVAL 5 MINUTE;

-- Kafka consumer lag
SELECT topic, partition, current_offset - last_offset AS lag
FROM system.kafka_consumer_lag
WHERE database = 'ipdr';
```

## Project Structure

```
ipdr-platform/
├── docker-compose.yml              # Main orchestration file
├── .env                            # Environment configuration (git-ignored)
├── .env.example                    # Example environment file
├── .gitignore                      # Git ignore rules
├── README.md                       # This file
├── syslog-ng/                      # Syslog-ng collector
│   ├── Dockerfile                  # linuxserver/syslog-ng:4.10.2 based
│   └── config/
│       └── syslog-ng.conf          # Log parsing & routing rules
├── kafka/                          # Apache Kafka (KRaft mode, official image)
│   ├── Dockerfile                  # Custom image with init script support
│   ├── entrypoint.sh               # Custom entrypoint (start → init scripts → foreground)
│   └── scripts/
│       └── create-topics.sh        # Auto-create ipdr-events & security-events on boot
├── kafka-consumer/                  # Node.js Kafka → ClickHouse consumer
│   ├── Dockerfile                  # Multi-stage production image
│   ├── package.json
│   └── src/
│       ├── index.js                # Entry point with graceful shutdown
│       ├── config.js               # Environment-based configuration
│       ├── logger.js               # Pino structured logger
│       ├── clickhouse.js           # Batch inserter with retry + DLQ
│       └── consumer.js             # Kafka consumer + message parser
├── clickhouse/                     # ClickHouse database
│   ├── config.d/
│   │   ├── config.xml              # Server config overrides
│   │   └── macros.xml              # Shard/replica macros
│   ├── users.d/
│   │   └── users.xml               # Users, profiles, quotas
│   └── migrations/                  # Schema migrations (run on startup)
│       ├── 001_create_database.sql
│       ├── 002_create_ipdr_records.sql
│       ├── 003_create_daily_aggregation.sql
│       ├── 004_create_kafka_consumer.sql
│       ├── 005_create_analytics_views.sql  # Hourly, destinations, apps, bandwidth
│       └── run.sh                  # Migration runner
├── grafana/                        # Grafana dashboards
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── clickhouse.yaml     # Auto-provision ClickHouse datasource
│   │   └── dashboards/
│   │       └── default.yaml        # Dashboard provider config
│   └── dashboards/
│       ├── ipdr-overview.json              # Main platform overview
│       ├── ipdr-traffic-volume.json        # Traffic volume analytics
│       ├── ipdr-subscriber-ranking.json    # Subscriber bandwidth ranking
│       ├── ipdr-bandwidth-usage.json       # Bandwidth breakdown by service
│       └── ipdr-protocol-distribution.json # Protocol & application distribution
└── scripts/
    ├── setup.sh                    # Initial setup & validation
    └── check-health.sh             # Health check utility
```
