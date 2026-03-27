#!/usr/bin/env python3

import re
import sys
from pathlib import Path
from collections import defaultdict

# --- CLI input ---
if len(sys.argv) < 2:
    print("Usage: python read-logs.py <logfile>")
    sys.exit(1)

log_path = Path(sys.argv[1])
if not log_path.exists():
    print(f"File not found: {log_path}")
    sys.exit(1)

# --- Read log lines ---
with open(log_path, "r") as f:
    lines = f.readlines()

order_logs = defaultdict(list)
order_id_pattern = r"(hbot-\d{13}-[a-z0-9]+-[A-Za-z0-9]+)"  # FIXED

# --- Collect all logs per order ---
for idx, line in enumerate(lines):
    match = re.search(order_id_pattern, line)
    if not match:
        continue
    order_id = match.group()
    order_logs[order_id].append({
        "line_number": idx + 1,
        "timestamp": line[:23],
        "content": line.strip()
    })

# --- Define groups ---
group1_filled_completed = {}
group2_completed_then_cancel = {}
group3_filled_then_cancelled = {}

# --- Process each order ---
for order_id, logs in order_logs.items():
    events = []
    cancelling_flag = False

    for log in logs:
        content = log["content"]
        if "OrderFilledEvent" in content:
            events.append("FILLED")
        elif "BuyOrderCompletedEvent" in content:
            events.append("BUY_COMPLETED")
        elif "SellOrderCompletedEvent" in content:
            events.append("SELL_COMPLETED")
        elif "OrderCancelledEvent" in content:
            events.append("CANCELLED")
        if "cancelling order" in content.lower():
            cancelling_flag = True

    event_string = ",".join(events)

    # Group 1: FILLED then Completed
    if "FILLED" in event_string and any(comp in event_string for comp in ["BUY_COMPLETED", "SELL_COMPLETED"]):
        if event_string.index("FILLED") < event_string.index("COMPLETED"):
            group1_filled_completed[order_id] = logs
            continue

    # Group 2: Completed then "cancelling order.."
    if cancelling_flag and any(e in events for e in ["BUY_COMPLETED", "SELL_COMPLETED"]):
        group2_completed_then_cancel[order_id] = logs
        continue

    # Group 3: FILLED then CANCELLED (no completed event)
    if "FILLED" in events and "CANCELLED" in events and not any(x in events for x in ["BUY_COMPLETED", "SELL_COMPLETED"]):
        group3_filled_then_cancelled[order_id] = logs

# --- Output Results ---
def print_group(group_dict, title):
    print(f"\n\n===== {title} ({len(group_dict)}) =====")
    for order_id, logs in group_dict.items():
        print(f"\n--- Order ID: {order_id} ---")
        for log in logs:
            print(f"[{log['line_number']}] {log['timestamp']} - {log['content']}")

# Print all 3 groups
print_group(group1_filled_completed, "GROUP 1: Filled → Completed")
print_group(group2_completed_then_cancel, "GROUP 2: Completed → Cancel Requested")
print_group(group3_filled_then_cancelled, "GROUP 3: Filled → Cancelled")

# --- Summary ---
print("\n\n===== SUMMARY =====")
print(f"Group 1 (Filled → Completed):  {len(group1_filled_completed)}")
print(f"Group 2 (Completed → Cancel Requested):  {len(group2_completed_then_cancel)}")
print(f"Group 3 (Filled → Cancelled): {len(group3_filled_then_cancelled)}")