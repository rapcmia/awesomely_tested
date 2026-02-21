#!/usr/bin/env python3

import re
import sys
from pathlib import Path
from collections import defaultdict

# --- CLI input ---
if len(sys.argv) < 2:
    print("Usage: python read-logs-light.py <logfile>")
    sys.exit(1)

log_path = Path(sys.argv[1])
if not log_path.exists():
    print(f"File not found: {log_path}")
    sys.exit(1)

# --- Read log lines ---
with open(log_path, "r") as f:
    lines = f.readlines()

order_logs = defaultdict(list)
order_id_pattern = r"(hbot-\d{13}-[a-z0-9]+-[A-Za-z0-9]+)"

# --- Group lines by order ID ---
for line in lines:
    match = re.search(order_id_pattern, line)
    if match:
        order_id = match.group()
        order_logs[order_id].append(line.strip())

# --- Define groups ---
group1 = []  # Filled → Completed
group2 = []  # Completed → Cancelling
group3 = []  # Filled → Cancelled

# --- Categorize orders ---
for order_id, logs in order_logs.items():
    events = []
    cancelling_flag = any("cancelling order" in log.lower() for log in logs)

    for log in logs:
        if "OrderFilledEvent" in log:
            events.append("FILLED")
        elif "BuyOrderCompletedEvent" in log:
            events.append("BUY_COMPLETED")
        elif "SellOrderCompletedEvent" in log:
            events.append("SELL_COMPLETED")
        elif "OrderCancelledEvent" in log:
            events.append("CANCELLED")

    event_string = ",".join(events)

    # Group 1: FILLED → Completed
    if "FILLED" in event_string and any(x in event_string for x in ["BUY_COMPLETED", "SELL_COMPLETED"]):
        if event_string.index("FILLED") < event_string.index("COMPLETED"):
            group1.append(order_id)
            continue

    # Group 2: Completed → Cancelling
    if cancelling_flag and any(x in events for x in ["BUY_COMPLETED", "SELL_COMPLETED"]):
        group2.append(order_id)
        continue

    # Group 3: FILLED → Cancelled (no completed)
    if "FILLED" in events and "CANCELLED" in events and not any(x in events for x in ["BUY_COMPLETED", "SELL_COMPLETED"]):
        group3.append(order_id)

# --- Output ---
def print_group(name, group):
    print(f"\n===== {name} ({len(group)}) =====")
    for order_id in group:
        print(order_id)

print_group("GROUP 1: Filled → Completed", group1)
print_group("GROUP 2: Completed → Cancel Requested", group2)
print_group("GROUP 3: Filled → Cancelled", group3)

print("\n===== SUMMARY =====")
print(f"Group 1: {len(group1)}")
print(f"Group 2: {len(group2)}")
print(f"Group 3: {len(group3)}")