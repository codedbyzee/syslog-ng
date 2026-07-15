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
echo "[init] Application user is managed by ClickHouse entrypoint (CLICKHOUSE_USER env var)."

# =============================================================================
# Kafka Engine Table — consumes from local Kafka broker
# =============================================================================

echo "[init] Creating Kafka engine table..."

clickhouse-client --query "
    CREATE TABLE IF NOT EXISTS ${DB}.kafka_ipdr (
        raw_message String
    ) ENGINE = Kafka
      SETTINGS
        kafka_broker_list = 'kafka:9092',
        kafka_topic_list = 'ipdr-events',
        kafka_group_name = 'clickhouse-ipdr',
        kafka_format = 'LineAsString',
        kafka_num_consumers = 1;
"

cat > /tmp/kafka_mv.sql << 'MVEOF'
CREATE MATERIALIZED VIEW IF NOT EXISTS __DB__.kafka_ipdr_mv
TO __DB__.ipdr_records AS
SELECT
    multiIf(
        JSONExtractString(extract(raw_message, '{.*}'), 'ISODATE') != '',
        parseDateTimeBestEffortOrZero(JSONExtractString(extract(raw_message, '{.*}'), 'ISODATE')),
        extract(raw_message, $$time='([^']+)'$$) != '',
        parseDateTimeBestEffortOrZero(extract(raw_message, $$time='([^']+)'$$)),
        extract(raw_message, $$^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})$$) != '',
        parseDateTimeBestEffortOrZero(extract(raw_message, $$^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})$$)),
        now()
    ) AS timestamp,
    multiIf(
        JSONExtractString(extract(raw_message, '{.*}'), 'collector_id') != '',
        JSONExtractString(extract(raw_message, '{.*}'), 'collector_id'),
        extract(raw_message, $$^\S+\s+\S+\s+(\S+)$$) != '',
        extract(raw_message, $$^\S+\s+\S+\s+(\S+)$$),
        extract(raw_message, $$(\S+:\s+\S+)\s+forward:$$) != '',
        extract(raw_message, $$(\S+:\s+\S+)\s+forward:$$),
        ''
    ) AS collector_id,
    multiIf(
        JSONExtractString(extract(raw_message, '{.*}'), 'subscriber_id') != '',
        JSONExtractString(extract(raw_message, '{.*}'), 'subscriber_id'),
        extract(raw_message, $$USERNAME="([^"]+)"$$) != '',
        extract(raw_message, $$USERNAME="([^"]+)"$$),
        extract(raw_message, $$in:<([^>]+)>$$) != '',
        extract(raw_message, $$in:<([^>]+)>$$),
        ''
    ) AS subscriber_id,
    IPv6StringToNum(
        multiIf(
            JSONExtractString(extract(raw_message, '{.*}'), 'source_ip') != '',
            JSONExtractString(extract(raw_message, '{.*}'), 'source_ip'),
            extract(raw_message, $$ISADDR="([^"]+)"$$) != '',
            extract(raw_message, $$ISADDR="([^"]+)"$$),
            extract(raw_message, $$(\d+\.\d+\.\d+\.\d+):\d+\s*->$$) != '',
            extract(raw_message, $$(\d+\.\d+\.\d+\.\d+):\d+\s*->$$),
            '::'
        )
    ) AS source_ip,
    IPv6StringToNum(
        multiIf(
            JSONExtractString(extract(raw_message, '{.*}'), 'destination_ip') != '',
            JSONExtractString(extract(raw_message, '{.*}'), 'destination_ip'),
            extract(raw_message, $$IDADDR="([^"]+)"$$) != '',
            extract(raw_message, $$IDADDR="([^"]+)"$$),
            extract(raw_message, $$->\s*(\d+\.\d+\.\d+\.\d+):\d+$$) != '',
            extract(raw_message, $$->\s*(\d+\.\d+\.\d+\.\d+):\d+$$),
            '::'
        )
    ) AS destination_ip,
    toUInt16OrDefault(
        multiIf(
            JSONExtractString(extract(raw_message, '{.*}'), 'source_port') != '',
            JSONExtractString(extract(raw_message, '{.*}'), 'source_port'),
            extract(raw_message, $$ISPORT="([^"]+)"$$) != '',
            extract(raw_message, $$ISPORT="([^"]+)"$$),
            extract(raw_message, $$\b\d+\.\d+\.\d+\.\d+:(\d+)\s*->$$) != '',
            extract(raw_message, $$\b\d+\.\d+\.\d+\.\d+:(\d+)\s*->$$),
            '0'
        )
    ) AS source_port,
    toUInt16OrDefault(
        multiIf(
            JSONExtractString(extract(raw_message, '{.*}'), 'destination_port') != '',
            JSONExtractString(extract(raw_message, '{.*}'), 'destination_port'),
            extract(raw_message, $$IDPORT="([^"]+)"$$) != '',
            extract(raw_message, $$IDPORT="([^"]+)"$$),
            extract(raw_message, $$->\s*\d+\.\d+\.\d+\.\d+:(\d+)$$) != '',
            extract(raw_message, $$->\s*\d+\.\d+\.\d+\.\d+:(\d+)$$),
            '0'
        )
    ) AS destination_port,
    lower(
        multiIf(
            JSONExtractString(extract(raw_message, '{.*}'), 'protocol') != '',
            JSONExtractString(extract(raw_message, '{.*}'), 'protocol'),
            extract(raw_message, $$PROTO="([^"]+)"$$) != '',
            extract(raw_message, $$PROTO="([^"]+)"$$),
            extract(raw_message, $$proto\s+(\w+)$$) != '',
            extract(raw_message, $$proto\s+(\w+)$$),
            ''
        )
    ) AS protocol,
    multiIf(
        JSONExtractString(extract(raw_message, '{.*}'), 'service_type') != '',
        JSONExtractString(extract(raw_message, '{.*}'), 'service_type'),
        'nat_session'
    ) AS service_type,
    JSONExtractString(extract(raw_message, '{.*}'), 'apn') AS apn,
    multiIf(
        JSONExtractString(extract(raw_message, '{.*}'), 'rat_type') != '',
        JSONExtractString(extract(raw_message, '{.*}'), 'rat_type'),
        extract(raw_message, $$IATYP="([^"]+)"$$) != '',
        extract(raw_message, $$IATYP="([^"]+)"$$),
        ''
    ) AS rat_type,
    toUInt64OrDefault(JSONExtractString(extract(raw_message, '{.*}'), 'bytes_in')) AS bytes_in,
    toUInt64OrDefault(JSONExtractString(extract(raw_message, '{.*}'), 'bytes_out')) AS bytes_out,
    toUInt64OrDefault(JSONExtractString(extract(raw_message, '{.*}'), 'packets_in')) AS packets_in,
    toUInt64OrDefault(JSONExtractString(extract(raw_message, '{.*}'), 'packets_out')) AS packets_out,
    toUInt32OrDefault(JSONExtractString(extract(raw_message, '{.*}'), 'duration_seconds')) AS duration_seconds,
    multiIf(
        JSONExtractString(extract(raw_message, '{.*}'), 'status') != '',
        JSONExtractString(extract(raw_message, '{.*}'), 'status'),
        extract(raw_message, 'SADD') != '',
        'active',
        extract(raw_message, 'SDEL') != '',
        'success',
        ''
    ) AS status,
    raw_message
FROM __DB__.kafka_ipdr
WHERE
    JSONExtractString(extract(raw_message, '{.*}'), 'subscriber_id') != ''
    OR extract(raw_message, $$USERNAME="([^"]+)"$$) != ''
    OR extract(raw_message, $$in:<([^>]+)>$$) != '';
MVEOF

sed "s/__DB__/${CLICKHOUSE_DB:-ipdr}/g" /tmp/kafka_mv.sql | clickhouse-client

echo "[init] Kafka engine table created. Data will start flowing into ipdr_records."
