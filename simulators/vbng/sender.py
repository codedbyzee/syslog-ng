import random
import socket
import time
from datetime import datetime, timezone

SYSLOG_HOST = "syslog-ng"
SYSLOG_PORT = 514

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

users = [f"sub{i:03d}" for i in range(1, 31)]
private_ips = [f"100.75.{random.randint(0, 10)}.{random.randint(1, 254)}" for _ in range(30)]
nat_ips = [f"59.103.61.{random.randint(10, 250)}" for _ in range(10)]

# Protocol number to name
PROTO_MAP = {"6": "tcp", "17": "udp", "1": "icmp", "47": "gre"}
PROTOCOLS = ["6", "17", "1", "47"]

def make_vbng_syslog(username, src_ip, dst_ip, src_port, dst_port, nat_ip, nat_port, proto, trigger, event_type):
    """Generate RFC 5424 syslog with [nsess ...] structured data (vBNG format)."""
    now = datetime.now(timezone.utc)
    timestamp = now.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    log_time = now.strftime("%Y-%m-%d %H:%M:%S")

    msgid = "SADD" if event_type == "session_start" else "SDEL"

    sd = (
        f'[nsess TRIG="{trigger}" PROTO="{proto}" SSUBIX="0" IATYP="IPv4" '
        f'USERNAME="{username}" ISADDR="{src_ip}" IDADDR="{dst_ip}" '
        f'ISPORT="{src_port}" IDPORT="{dst_port}" XATYP="IPv4" '
        f'XSADDR="{nat_ip}" XDADDR="{dst_ip}" XSPORT="{nat_port}" XDPORT="{dst_port}"]'
    )

    return f"<134>1 {timestamp} HG NAT 5964 {msgid} {sd} time='{log_time}'."


while True:
    username = random.choice(users)
    src_ip = random.choice(private_ips)
    dst_ip = f"{random.randint(1, 223)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"
    src_port = random.randint(1024, 65535)
    dst_port = random.choice([53, 80, 443, 8080, 3389])
    nat_ip = random.choice(nat_ips)
    nat_port = random.randint(10000, 65000)
    proto = random.choice(PROTOCOLS)
    trigger = random.choice(["OPKT", "APMDEL", "FIN", "RST"])

    # Send SADD (session start) first
    sadd = make_vbng_syslog(username, src_ip, dst_ip, src_port, dst_port, nat_ip, nat_port, proto, trigger, "session_start")
    sock.sendto(sadd.encode(), (SYSLOG_HOST, SYSLOG_PORT))
    print(f"[vBNG-SIM SADD] {username} {src_ip}:{src_port} -> {dst_ip}:{dst_port} (NAT {nat_ip}:{nat_port}) proto={proto}")

    time.sleep(random.uniform(1.0, 3.0))

    # Possibly send SDEL (session end)
    if random.random() < 0.4:
        sdel = make_vbng_syslog(username, src_ip, dst_ip, src_port, dst_port, nat_ip, nat_port, proto, "APMDEL", "session_end")
        sock.sendto(sdel.encode(), (SYSLOG_HOST, SYSLOG_PORT))
        print(f"[vBNG-SIM SDEL] {username} {src_ip}:{src_port} -> {dst_ip}:{dst_port} (NAT {nat_ip}:{nat_port}) proto={proto}")
