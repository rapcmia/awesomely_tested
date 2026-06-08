#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage:" >&2
  echo "  $0 <total_amount_in_usd> <order_amount_usd>" >&2
  echo "  $0 --pref" >&2
  echo "  $0 <default_total_amount_in_usd> --pref" >&2
}

normalize_decimal() {
  local n="$1"
  awk -v x="$n" 'BEGIN {
    s = sprintf("%.4f", x + 0)
    sub(/0+$/, "", s)
    sub(/\.$/, "", s)
    print s
  }'
}

usd_value() {
  local pct="$1"
  awk -v total="$total_amount" -v pct="$pct" 'BEGIN {
    s = sprintf("%.2f", total * pct)
    sub(/\.00$/, "", s)
    print s " USD"
  }'
}

clamp_to_max_pct() {
  local value="$1"
  local max="$2"
  awk -v value="$value" -v max="$max" 'BEGIN {
    if (value > max) {
      printf "%.10f", max
    } else {
      printf "%.10f", value
    }
  }'
}

is_numeric() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_positive() {
  awk -v n="$1" 'BEGIN { exit !(n > 0) }'
}

is_order_amount_valid() {
  awk -v n="$1" 'BEGIN { exit !(n >= 5) }'
}

validate_total_amount() {
  local value="$1"

  if ! is_numeric "$value"; then
    echo "Error: total amount must be a numeric USD value." >&2
    exit 1
  fi

  if ! is_positive "$value"; then
    echo "Error: total amount must be greater than 0." >&2
    exit 1
  fi
}

validate_order_amount() {
  local value="$1"

  if ! is_numeric "$value"; then
    echo "Error: order amount must be a numeric USD value." >&2
    exit 1
  fi

  if ! is_order_amount_valid "$value"; then
    echo "Error: order amount must be at least 5 USD." >&2
    exit 1
  fi
}

prompt_total_amount() {
  local default="${1:-}"
  local prompt="whats your total amount >> "
  local value

  [[ -n "$default" ]] && prompt="whats your total amount [$default] >> "

  while true; do
    read -r -p "$prompt" value
    [[ -z "$value" && -n "$default" ]] && value="$default"

    if is_numeric "$value" && is_positive "$value"; then
      printf '%s' "$value"
      return
    fi

    echo "Please enter a numeric total amount greater than 0."
  done
}

prompt_order_amount() {
  local value

  read -r -p "whats your order amount [5] USD >> " value
  [[ -z "$value" ]] && value="5"

  if ! is_numeric "$value"; then
    echo "Error: order amount must be a numeric USD value." >&2
    exit 1
  fi

  if ! is_order_amount_valid "$value"; then
    echo "Error: order amount must be at least 5 USD." >&2
    exit 1
  fi

  printf '%s' "$value"
}

number_of_orders=2

case "$#" in
  1)
    if [[ "$1" != "--pref" ]]; then
      usage
      exit 1
    fi
    echo
    total_amount="$(prompt_total_amount)"
    order_amount="$(prompt_order_amount)"
    ;;
  2)
    if [[ "$2" == "--pref" ]]; then
      validate_total_amount "$1"
      echo
      total_amount="$(prompt_total_amount "$1")"
      order_amount="$(prompt_order_amount)"
    else
      total_amount="$1"
      order_amount="$2"
      validate_total_amount "$total_amount"
      validate_order_amount "$order_amount"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac

portfolio_allocation_raw="$(
  awk -v order="$order_amount" -v total="$total_amount" -v orders="$number_of_orders" \
    'BEGIN { printf "%.10f", (order * orders) / total }'
)"
portfolio_allocation="$(normalize_decimal "$portfolio_allocation_raw")"
min_base_pct_raw="$(
  awk -v order="$order_amount" -v total="$total_amount" 'BEGIN { printf "%.10f", order / total }'
)"
min_base_pct="$(normalize_decimal "$min_base_pct_raw")"
target_base_pct_raw="$(
  awk -v min_base="$min_base_pct_raw" 'BEGIN { printf "%.10f", min_base * 2 }'
)"
target_base_pct="$(normalize_decimal "$target_base_pct_raw")"
max_base_pct_raw="$(
  awk 'BEGIN { printf "%.10f", 0.7 }'
)"
max_base_pct="$(normalize_decimal "$max_base_pct_raw")"

used_amount="$(usd_value "$portfolio_allocation_raw")"

echo
echo "+----------------------+------------+------------+"
echo "| value                | pct        | usd        |"
echo "+----------------------+------------+------------+"
printf "| %-20s | %-10s | %-10s |\n" "portfolio_allocation" "$portfolio_allocation" "$used_amount"
printf "| %-20s | %-10s | %-10s |\n" "min_base_pct" "$min_base_pct" "$(usd_value "$min_base_pct_raw")"
printf "| %-20s | %-10s | %-10s |\n" "target_base_pct" "$target_base_pct" "$(usd_value "$target_base_pct_raw")"
printf "| %-20s | %-10s | %-10s |\n" "max_base_pct" "$max_base_pct" "$(usd_value "$max_base_pct_raw")"
echo "+----------------------+------------+------------+"
echo
echo "- Using ${number_of_orders} orders at ${order_amount} USD each: ${used_amount} allocated from ${total_amount} USD."
echo "- portfolio_allocation: total amount allocated for the ${number_of_orders} orders."
echo "- min_base_pct: based on the order amount as a share of the total amount."
echo "- target_base_pct: 2x min_base_pct."
echo "- max_base_pct: fixed at 70% of the total amount."
echo
