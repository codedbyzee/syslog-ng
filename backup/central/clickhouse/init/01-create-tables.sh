#!/bin/bash
# =============================================================================
# ClickHouse Init — IPDR Tables & Schema
# =============================================================================
# Uses env vars: CLICKHOUSE_DB, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD
# Mapped to:    $DB, $USER, $PASS
# If CLICKHOUSE_USER is set and not 'default', creates a dedicated app user
# with full grants. Otherwise, the default user (managed by entrypoint) is used.
# =============================================================================

DB="${CLICKHOUSE_DB:?CLICKHOUSE_DB not set}"
USER="${CLICKHOUSE_USER:?CLICKHOUSE_USER not set}"
PASS="${CLICKHOUSE_PASSWORD:?CLICKHOUSE_PASSWORD not set}"

# Only create a dedicated app user if USER is explicitly set
# to something other than 'default' (which is managed by the entrypoint in XML)
if [ -n "${USER:-}" ] && [ "${USER}" != "default" ]; then
    echo "[init] Creating application user '${USER}'..."

    clickhouse-client --query "
        CREATE USER IF NOT EXISTS ${USER}
        IDENTIFIED WITH plaintext_password BY '${PASS}'
        DEFAULT DATABASE ${DB}
        SETTINGS PROFILE 'default';
        GRANT ALL ON ${DB}.* TO ${USER};
    "
fi

echo "[init] Creating grafana read-only user..."

clickhouse-client --query "
    CREATE USER IF NOT EXISTS grafana
    SETTINGS PROFILE 'default';
    GRANT SELECT ON ${DB}.* TO grafana;
"

echo "[init] Creating tables in database '${DB}'..."

clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.ipdr_records (
    timestamp DateTime, collector_id LowCardinality(String),
    subscriber_id String, subscriber_ip IPv6, imsi String, imei String, msisdn String,
    source_ip IPv6, destination_ip IPv6, source_port UInt16, destination_port UInt16,
    protocol LowCardinality(String), service_type LowCardinality(String), apn LowCardinality(String),
    rat_type LowCardinality(String), cell_id String,
    bytes_in UInt64, bytes_out UInt64, bytes_total UInt64 MATERIALIZED bytes_in + bytes_out,
    packets_in UInt64, packets_out UInt64, duration_seconds UInt32,
    status LowCardinality(String), cause_code String, charging_id String,
    raw_message String, parsed_at DateTime MATERIALIZED now()
) ENGINE = MergeTree() PARTITION BY toYYYYMM(timestamp)
  ORDER BY (subscriber_id, timestamp) TTL timestamp + INTERVAL 90 DAY
  SETTINGS index_granularity = 8192;
"

clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.ipdr_daily_aggregation (
    day Date, subscriber_id String, service_type LowCardinality(String),
    apn LowCardinality(String), rat_type LowCardinality(String),
    session_count UInt64, total_bytes_in UInt64, total_bytes_out UInt64, total_bytes UInt64,
    total_packets_in UInt64, total_packets_out UInt64, avg_duration_sec Float64,
    max_duration_sec UInt32, total_duration_sec UInt64, error_count UInt64,
    unique_destinations UInt64, unique_cells UInt64
) ENGINE = SummingMergeTree() PARTITION BY toYYYYMM(day)
  ORDER BY (day, subscriber_id, service_type, apn, rat_type)
  TTL day + INTERVAL 365 DAY SETTINGS index_granularity = 8192;
"

clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.ipdr_daily_aggregation_mv
TO ${DB}.ipdr_daily_aggregation AS
SELECT toDate(timestamp) AS day, subscriber_id, service_type, apn, rat_type,
    count() AS session_count, sum(bytes_in) AS total_bytes_in, sum(bytes_out) AS total_bytes_out,
    sum(bytes_total) AS total_bytes, sum(packets_in) AS total_packets_in, sum(packets_out) AS total_packets_out,
    avg(duration_seconds) AS avg_duration_sec, max(duration_seconds) AS max_duration_sec,
    sum(duration_seconds) AS total_duration_sec, countIf(status != 'success') AS error_count,
    uniqExact(destination_ip) AS unique_destinations, uniqExact(cell_id) AS unique_cells
FROM ${DB}.ipdr_records GROUP BY day, subscriber_id, service_type, apn, rat_type;
"

clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.ipdr_hourly_traffic (
    hour DateTime, service_type LowCardinality(String), protocol LowCardinality(String),
    rat_type LowCardinality(String), session_count UInt64, total_bytes_in UInt64,
    total_bytes_out UInt64, total_bytes UInt64, total_packets_in UInt64, total_packets_out UInt64,
    total_duration_sec UInt64, avg_duration_sec Float64, unique_subscribers UInt64,
    unique_destinations UInt64, error_count UInt64
) ENGINE = SummingMergeTree() PARTITION BY toYYYYMM(hour)
  ORDER BY (hour, service_type, protocol, rat_type)
  TTL hour + INTERVAL 90 DAY SETTINGS index_granularity = 8192;
"

clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.ipdr_hourly_traffic_mv
TO ${DB}.ipdr_hourly_traffic AS
SELECT toStartOfHour(timestamp) AS hour, service_type, protocol, rat_type,
    count() AS session_count, sum(bytes_in) AS total_bytes_in, sum(bytes_out) AS total_bytes_out,
    sum(bytes_total) AS total_bytes, sum(packets_in) AS total_packets_in, sum(packets_out) AS total_packets_out,
    sum(duration_seconds) AS total_duration_sec, avg(duration_seconds) AS avg_duration_sec,
    uniqExact(subscriber_id) AS unique_subscribers, uniqExact(destination_ip) AS unique_destinations,
    countIf(status != 'success') AS error_count
FROM ${DB}.ipdr_records GROUP BY hour, service_type, protocol, rat_type;
"

clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.ipdr_top_destinations (
    day Date, destination_ip IPv6, service_type LowCardinality(String),
    protocol LowCardinality(String), session_count UInt64, total_bytes UInt64,
    total_packets UInt64, total_duration_sec UInt64, unique_subscribers UInt64, unique_source_ports UInt64
) ENGINE = SummingMergeTree() PARTITION BY toYYYYMM(day)
  ORDER BY (day, destination_ip, service_type, protocol)
  TTL day + INTERVAL 90 DAY SETTINGS index_granularity = 8192;
"

clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.ipdr_top_destinations_mv
TO ${DB}.ipdr_top_destinations AS
SELECT toDate(timestamp) AS day, destination_ip, service_type, protocol,
    count() AS session_count, sum(bytes_total) AS total_bytes, sum(packets_in + packets_out) AS total_packets,
    sum(duration_seconds) AS total_duration_sec, uniqExact(subscriber_id) AS unique_subscribers,
    uniqExact(source_port) AS unique_source_ports
FROM ${DB}.ipdr_records GROUP BY day, destination_ip, service_type, protocol;
"

clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.ipdr_top_applications (
    day Date, service_type LowCardinality(String), protocol LowCardinality(String),
    apn LowCardinality(String), session_count UInt64, total_bytes_in UInt64,
    total_bytes_out UInt64, total_bytes UInt64, total_packets_in UInt64, total_packets_out UInt64,
    total_duration_sec UInt64, avg_duration_sec Float64, unique_subscribers UInt64, bytes_per_second Float64
) ENGINE = SummingMergeTree() PARTITION BY toYYYYMM(day)
  ORDER BY (day, service_type, protocol, apn)
  TTL day + INTERVAL 180 DAY SETTINGS index_granularity = 8192;
"

clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.ipdr_top_applications_mv
TO ${DB}.ipdr_top_applications AS
SELECT toDate(timestamp) AS day, service_type, protocol, apn,
    count() AS session_count, sum(bytes_in) AS total_bytes_in, sum(bytes_out) AS total_bytes_out,
    sum(bytes_total) AS total_bytes, sum(packets_in) AS total_packets_in, sum(packets_out) AS total_packets_out,
    sum(duration_seconds) AS total_duration_sec, avg(duration_seconds) AS avg_duration_sec,
    uniqExact(subscriber_id) AS unique_subscribers,
    if(sum(duration_seconds) > 0, sum(bytes_total) / sum(duration_seconds), 0) AS bytes_per_second
FROM ${DB}.ipdr_records GROUP BY day, service_type, protocol, apn;
"

clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.ipdr_subscriber_bandwidth (
    day Date, subscriber_id String, service_type LowCardinality(String),
    rat_type LowCardinality(String), session_count UInt64, total_bytes_in UInt64,
    total_bytes_out UInt64, total_bytes UInt64, max_bytes_in_session UInt64,
    max_bytes_out_session UInt64, total_packets_in UInt64, total_packets_out UInt64,
    total_duration_sec UInt64, avg_duration_sec Float64, max_duration_sec UInt32,
    error_count UInt64, unique_destinations UInt64, unique_apns UInt64
) ENGINE = SummingMergeTree() PARTITION BY toYYYYMM(day)
  ORDER BY (day, subscriber_id, service_type, rat_type)
  TTL day + INTERVAL 365 DAY SETTINGS index_granularity = 8192;
"

clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.ipdr_subscriber_bandwidth_mv
TO ${DB}.ipdr_subscriber_bandwidth AS
SELECT toDate(timestamp) AS day, subscriber_id, service_type, rat_type,
    count() AS session_count, sum(bytes_in) AS total_bytes_in, sum(bytes_out) AS total_bytes_out,
    sum(bytes_total) AS total_bytes, max(bytes_in) AS max_bytes_in_session, max(bytes_out) AS max_bytes_out_session,
    sum(packets_in) AS total_packets_in, sum(packets_out) AS total_packets_out,
    sum(duration_seconds) AS total_duration_sec, avg(duration_seconds) AS avg_duration_sec,
    max(duration_seconds) AS max_duration_sec, countIf(status != 'success') AS error_count,
    uniqExact(destination_ip) AS unique_destinations, uniqExact(apn) AS unique_apns
FROM ${DB}.ipdr_records GROUP BY day, subscriber_id, service_type, rat_type;
"

echo "[init] IPDR schema initialization complete."
if [ -n "${USER:-}" ] && [ "${USER}" != "default" ]; then
    echo "[init] Application user '${USER}' is ready with full access to ${DB}.*"
else
    echo "[init] Using default user (managed by entrypoint)"
fi

# =============================================================================
# Kafka Engine Tables — one per site
# Each connects to a remote site's Kafka broker over the WAN.
# Add new sites by adding a create_site_kafka_table call below.
# =============================================================================

echo "[init] Creating Kafka engine tables for registered sites..."

# Creates a Kafka engine table + Materialized View for one site
create_site_kafka_table() {
    local SITE_ID="$1"
    local KAFKA_HOST="$2"
    local KAFKA_PORT="${3:-9094}"

    # Sanitize: replace hyphens with underscores (ClickHouse table names)
    local SAFE_ID="${SITE_ID//-/_}"

    echo "[init]   Registering site '${SITE_ID}' at ${KAFKA_HOST}:${KAFKA_PORT}..."

    clickhouse-client --query "
        CREATE TABLE IF NOT EXISTS ${DB}.kafka_${SAFE_ID} (
            raw_message String
        ) ENGINE = Kafka
          SETTINGS
            kafka_broker_list = '${KAFKA_HOST}:${KAFKA_PORT}',
            kafka_topic_list = 'ipdr-events',
            kafka_group_name = 'clickhouse-${SITE_ID}',
            kafka_format = 'LineAsString',
            kafka_num_consumers = 1;
    "

    clickhouse-client --query "
        CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.kafka_${SAFE_ID}_mv
        TO ${DB}.ipdr_records AS
        SELECT
            parseDateTimeBestEffortOrZero(
                JSONExtractString(raw_message, 'ISODATE')
            ) AS timestamp,
            JSONExtractString(raw_message, '.ipdr.subscriber_id') AS subscriber_id,
            IPv6StringToNum(
                CASE WHEN JSONExtractString(raw_message, '.ipdr.source_ip') = '' THEN '::'
                     ELSE JSONExtractString(raw_message, '.ipdr.source_ip') END
            ) AS source_ip,
            IPv6StringToNum(
                CASE WHEN JSONExtractString(raw_message, '.ipdr.destination_ip') = '' THEN '::'
                     ELSE JSONExtractString(raw_message, '.ipdr.destination_ip') END
            ) AS destination_ip,
            toUInt16OrDefault(
                JSONExtractString(raw_message, '.ipdr.source_port')
            ) AS source_port,
            toUInt16OrDefault(
                JSONExtractString(raw_message, '.ipdr.destination_port')
            ) AS destination_port,
            lower(
                JSONExtractString(raw_message, '.ipdr.protocol')
            ) AS protocol,
            JSONExtractString(raw_message, '.ipdr.service_type') AS service_type,
            toUInt64OrDefault(
                JSONExtractString(raw_message, '.ipdr.bytes_in')
            ) AS bytes_in,
            toUInt64OrDefault(
                JSONExtractString(raw_message, '.ipdr.bytes_out')
            ) AS bytes_out,
            toUInt64OrDefault(
                JSONExtractString(raw_message, '.ipdr.packets_in')
            ) AS packets_in,
            toUInt64OrDefault(
                JSONExtractString(raw_message, '.ipdr.packets_out')
            ) AS packets_out,
            toUInt32OrDefault(
                JSONExtractString(raw_message, '.ipdr.duration_seconds')
            ) AS duration_seconds,
            JSONExtractString(raw_message, '.ipdr.status') AS status,
            JSONExtractString(raw_message, 'MESSAGE') AS raw_message
        FROM ${DB}.kafka_${SAFE_ID}
        WHERE JSONExtractString(raw_message, '.ipdr.subscriber_id') != '';
    "
}

# ── Register sites ────────────────────────────────────────────────────
# Add/remove lines below to add/remove sites.
# After editing, restart ClickHouse: docker compose restart clickhouse

# For production, replace with actual site addresses:
# create_site_kafka_table "site-a" "kafka-site-a.yourcompany.com" 9094
# create_site_kafka_table "site-b" "kafka-site-b.yourcompany.com" 9094

# Local dev — Kafka is on the same Docker network (ipdr-shared)
create_site_kafka_table "site-a" "kafka" 9092

echo "[init] Kafka engine tables created. Data will start flowing from registered sites."
