import random
import socket
import time
from datetime import datetime, timezone

SYSLOG_HOST = "syslog-ng"
SYSLOG_PORT = 514

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

users = [f"pppoe-{random.choice(['jmal', 'asad', 'zeeshan', 'bilal', 'umer', 'farhan', 'ali', 'saad', 'omar', 'hassan'])}{random.randint(100, 999)}" for _ in range(30)]
device_tags = ["WCT-L7", "WCT-L3", "WCT-L5", "WCT-L2", "WCT-L9"]
device_labels = [f"WT-LT-{random.randint(1, 30)}-BRAS{random.randint(1, 20)}" for _ in range(20)]
local_ips = [f"10.10.{random.randint(1, 20)}.{random.randint(1, 254)}" for _ in range(50)]
public_ips = [f"163.61.137.{random.randint(100, 250)}" for _ in range(20)]
dest_ips = [f"{random.randint(1, 223)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}" for _ in range(50)]
dest_ports = [53, 80, 443, 8080, 3389, 22]
src_macs = [f"68:e2:09:cc:{random.randint(0, 255):02x}:{random.randint(0, 255):02x}" for _ in range(30)]
protocols = ["TCP", "UDP", "ICMP"]

def make_mikrotik_syslog(username, device_tag, device_label, src_ip, src_port, dst_ip, dst_port, nat_ip, nat_port, proto, mac):
    """Generate MikroTik-formatted syslog message."""
    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "+05:00"
    conn_state = random.choice(["established", "new", "related"])
    snat_flag = "snat" if random.random() < 0.8 else ""
    proto_flag = f" ({random.choice(['ACK', 'SYN', 'SYN,ACK', 'FIN'])}), " if proto == "TCP" else ", "
    pkt_len = random.randint(40, 1500)

    msg = (
        f"{ts}  {device_tag}: {device_label} forward: "
        f"in:<{username}> out:{random.randint(1000, 9999)}, "
        f"connection-state:{conn_state},{snat_flag} "
        f"src-mac {mac}, "
        f"proto {proto}{proto_flag}"
        f"{src_ip}:{src_port}->{dst_ip}:{dst_port}, "
        f"NAT ({src_ip}:{src_port}->{nat_ip}:{nat_port})->{dst_ip}:{dst_port}, "
        f"len {pkt_len}"
    )
    return msg


while True:
    username = random.choice(users)
    device_tag = random.choice(device_tags)
    device_label = random.choice(device_labels)
    src_ip = random.choice(local_ips)
    dst_ip = random.choice(dest_ips)
    src_port = random.randint(1024, 65535)
    dst_port = random.choice(dest_ports)
    nat_ip = random.choice(public_ips)
    nat_port = src_port  # MikroTik often preserves the port
    proto = random.choice(protocols)
    mac = random.choice(src_macs)

    msg = make_mikrotik_syslog(username, device_tag, device_label, src_ip, src_port, dst_ip, dst_port, nat_ip, nat_port, proto, mac)
    sock.sendto(msg.encode(), (SYSLOG_HOST, SYSLOG_PORT))
    print(f"[MIKROTIK-SIM] {device_tag}:{device_label} {username} {src_ip}:{src_port} -> {dst_ip}:{dst_port} via {nat_ip}:{nat_port}")
    time.sleep(random.uniform(0.3, 1.5))
