#!/bin/bash
# Save as: memleak-check.sh

CONTAINER_NAME="pmm_btcfdusd"
LOGDIR="/home/hummingbot/ralph/script-logs"
DATE_TAG=$(date +%m%d%Y)
LOGFILE="${LOGDIR}/${DATE_TAG}-mem-monitoring.log"

# ANSI color codes
RED='\033[0;31m'
NC='\033[0m'  # No Color

# Create log directory if it doesn't exist
mkdir -p "$LOGDIR"

# Clear terminal and show startup message
clear
echo
echo "Ralph: ♻️  Memleak app running"
echo "Please don’t close this terminal"
echo "Logging to: $LOGFILE"
echo

# Log file header
echo -e "DATE\t\t\tCONTAINER\tCPU %\t\tMEM USAGE / LIMIT" >> "$LOGFILE"

# Handle Ctrl+C to mark exit in log
trap 'echo -e "\n❌ Logging stopped at: $(date)" >> "$LOGFILE"; exit 0' SIGINT

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    STATS=$(docker stats "$CONTAINER_NAME" --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -n 1)

    NAME=$(echo "$STATS" | awk '{print $1}')
    CPU=$(echo "$STATS" | awk '{print $2}')
    MEM_FULL=$(echo "$STATS" | awk '{print $3 " " $4 " " $5}')
    MEM_USED=$(echo "$MEM_FULL" | awk '{print $1}')
    MEM_TOTAL=$(echo "$MEM_FULL" | awk '{print $3}')

    # Convert to MiB for checks
    USED_MIB=$(echo "$MEM_USED" | sed 's/MiB//;s/GiB/*1024/;s/KiB/\/1024/' | bc -l)
    TOTAL_MIB=$(echo "$MEM_TOTAL" | sed 's/MiB//;s/GiB/*1024/;s/KiB/\/1024/' | bc -l)

    # Safety check
    if [[ -z "$USED_MIB" || -z "$TOTAL_MIB" || "$TOTAL_MIB" == "0" ]]; then
        PERCENT=0
    else
        PERCENT=$(echo "$USED_MIB $TOTAL_MIB" | awk '{printf "%.0f", ($1 / $2) * 100}')
    fi

    # Log to file always
    echo -e "${TIMESTAMP}\t$NAME\t$CPU\t$MEM_FULL" >> "$LOGFILE"

    # Alert to terminal if usage exceeds 800 MiB
    USAGE_LIMIT=800
    ABOVE_LIMIT=$(echo "$USED_MIB > $USAGE_LIMIT" | bc -l)

    if [ "$ABOVE_LIMIT" -eq 1 ]; then
        echo -e "High memory: ${TIMESTAMP}\t$CPU\t$MEM_FULL${NC}"
    fi

    sleep 5
done
