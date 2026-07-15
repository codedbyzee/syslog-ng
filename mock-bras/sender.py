import json
import random
import socket
import time
from datetime import datetime, timezone

SYSLOG_HOST = "syslog-ng"
SYSLOG_PORT = 514

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

users = [f"user{i:03d}" for i in range(1, 21)]
services = ["PPPoE", "LTE", "VoIP", "IPTV", "VPN"]
protocols = ["tcp", "udp", "icmp"]
statuses = ["success", "success", "success", "success", "failed"]

while True:
    record = {
        "ISODATE": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
        "subscriber_id": random.choice(users),
        "source_ip": f"10.10.{random.randint(1, 20)}.{random.randint(1, 254)}",
        "destination_ip": f"{random.randint(1, 223)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}",
        "source_port": random.randint(1024, 65535),
        "destination_port": random.choice([80, 443, 53, 22, 8080, 3389]),
        "protocol": random.choice(protocols),
        "service_type": random.choice(services),
        "apn": random.choice(["internet", "ims", "vpn", "mms", "wap"]),
        "rat_type": random.choice(["LTE", "5G", "NR"]),
        "bytes_in": random.randint(1000, 50_000_000),
        "bytes_out": random.randint(1000, 50_000_000),
        "packets_in": random.randint(10, 50_000),
        "packets_out": random.randint(10, 50_000),
        "duration_seconds": random.randint(5, 3600),
        "status": random.choice(statuses),
    }

    message = json.dumps(record)

    sock.sendto(message.encode(), (SYSLOG_HOST, SYSLOG_PORT))
    print(f"[{datetime.now(timezone.utc).isoformat()}] {message}")

    time.sleep(random.uniform(0.5, 2.0))