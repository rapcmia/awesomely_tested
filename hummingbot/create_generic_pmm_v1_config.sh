#!/usr/bin/env bash
set -euo pipefail

# README
# 1) Place this script in the root project folder.
# 2) Make it executable once:
#    chmod +x create_generic_pmm_v1_config.sh
# 3) Run from root:
#    bash create_generic_pmm_v1_config.sh
#    or
#    ./create_generic_pmm_v1_config.sh

CONTROLLER_CONFIG_DIR="conf/controllers"
SCRIPT_CONFIG_DIR="conf/scripts"

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

prompt_default() {
  local label="$1"
  local default="$2"
  local value
  read -r -p "$label [$default]: " value
  value="$(trim "$value")"
  [[ -z "$value" ]] && value="$default"
  printf '%s' "$value"
}

prompt_int() {
  local label="$1"
  local default="$2"
  local value
  while true; do
    read -r -p "$label [$default]: " value
    value="$(trim "$value")"
    [[ -z "$value" ]] && value="$default"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      printf '%s' "$value"
      return
    fi
    echo "Please enter an integer." >&2
  done
}

prompt_bool() {
  local label="$1"
  local default="$2"
  local value
  while true; do
    value="$(prompt_default "$label (true/false)" "$default")"
    value="${value,,}"
    case "$value" in
      true|false)
        printf '%s' "$value"
        return
        ;;
      *)
        echo "Please enter true or false." >&2
        ;;
    esac
  done
}

sanitize_suffix() {
  local raw="$1"
  local cleaned
  cleaned="$(printf '%s' "$raw" | tr ' ' '_' | tr -cd '[:alnum:]_-')"
  printf '%s' "$cleaned"
}

next_default_controller_id() {
  local date_prefix="$1"
  local max_n=0
  local file base num

  for file in "${CONTROLLER_CONFIG_DIR}/${date_prefix}"_pmmv1*.yml; do
    [[ -e "$file" ]] || continue
    base="$(basename "$file" .yml)"
    if [[ "$base" =~ ^${date_prefix}_pmmv1_([0-9]+)$ ]]; then
      num="${BASH_REMATCH[1]}"
      num=$((10#$num))
      (( num > max_n )) && max_n=$num
    elif [[ "$base" =~ ^${date_prefix}_pmmv1([0-9]+)$ ]]; then
      # Backward compatibility with older naming without underscore.
      num="${BASH_REMATCH[1]}"
      num=$((10#$num))
      (( num > max_n )) && max_n=$num
    fi
  done

  printf '%s_pmmv1_%02d' "$date_prefix" $((max_n + 1))
}

script_config_filename_for_controller() {
  local controller_id="$1"
  local date_prefix="${controller_id%%_*}"
  local suffix="${controller_id#*_}"

  if [[ "$controller_id" == "$suffix" ]]; then
    printf 'conf_generic_pmm_v1_%s.yml' "$controller_id"
  else
    printf '%s_conf_generic_pmm_v1_%s.yml' "$date_prefix" "$suffix"
  fi
}

csv_to_yaml_float_list() {
  local csv="$1"
  IFS=',' read -r -a arr <<< "$csv"
  for item in "${arr[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && echo "- $item"
  done
}

if [[ ! -d "$CONTROLLER_CONFIG_DIR" ]]; then
  echo "Output directory '$CONTROLLER_CONFIG_DIR' not found."
  exit 1
fi
mkdir -p "$SCRIPT_CONFIG_DIR"

echo "Create generic.pmm_v1 controller config"
echo "---------------------------------------"
echo "Note:"
echo "- Press Enter to accept the default value shown in [brackets]."
echo "- PMM V1 uses order_amount (BASE asset) for sizing. total_amount_quote is fixed to 0."
echo "- price_ceiling=-1 and price_floor=-1 mean disabled."
echo

date_prefix="$(date +%d%m%Y)"
read -r -p "Enter config name suffix (blank for auto): " user_suffix
user_suffix="$(trim "${user_suffix:-}")"

if [[ -z "$user_suffix" ]]; then
  config_id="$(next_default_controller_id "$date_prefix")"
else
  user_suffix="$(sanitize_suffix "$user_suffix")"
  if [[ -z "$user_suffix" ]]; then
    echo "Invalid suffix. Use letters, numbers, _ or -."
    exit 1
  fi
  config_id="${date_prefix}_${user_suffix}"
fi

controller_filename="${config_id}.yml"
controller_path="${CONTROLLER_CONFIG_DIR}/${controller_filename}"

if [[ -f "$controller_path" ]]; then
  read -r -p "File already exists: $controller_path. Overwrite? (y/N): " overwrite
  overwrite="$(trim "$overwrite")"
  if [[ "${overwrite,,}" != "y" && "${overwrite,,}" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# Prompted fields (non-# in baseline)
connector_name="$(prompt_default "connector_name" "kucoin")"
trading_pair="$(prompt_default "trading_pair" "SOL-USDT")"
base_asset="${trading_pair%%-*}"
order_amount="$(prompt_default "order_amount in BASE asset (e.g., 0.057 ${base_asset})" "0.057")"
buy_spreads_csv="$(prompt_default "buy_spreads (comma-separated decimals)" "0.01")"
sell_spreads_csv="$(prompt_default "sell_spreads (comma-separated decimals)" "0.01")"
order_refresh_time="$(prompt_int "order_refresh_time (seconds)" "30")"
inventory_skew_enabled="$(prompt_bool "inventory_skew_enabled" "false")"
if [[ "$inventory_skew_enabled" == "true" ]]; then
  target_base_pct="$(prompt_default "target_base_pct" "0.5")"
else
  target_base_pct="0.5"
fi

# No-prompt defaults from baseline (#) + controller defaults
total_amount_quote="0"
manual_kill_switch="false"
order_refresh_tolerance_pct="-1"
filled_order_delay="60"
inventory_range_multiplier="1.0"
price_ceiling="-1"
price_floor="-1"

buy_spreads_yaml="$(csv_to_yaml_float_list "$buy_spreads_csv")"
sell_spreads_yaml="$(csv_to_yaml_float_list "$sell_spreads_csv")"

cat > "$controller_path" <<YAML
id: ${config_id}
controller_name: pmm_v1
controller_type: generic
total_amount_quote: '${total_amount_quote}' # Fixed to 0 for PMM V1; strategy uses order_amount instead.
manual_kill_switch: ${manual_kill_switch} # Emergency global stop switch.
initial_positions: [] # Starts without seeded positions.
connector_name: ${connector_name}
trading_pair: ${trading_pair}
order_amount: '${order_amount}' # Base asset size per order (e.g., ${order_amount} ${base_asset}).
buy_spreads:
${buy_spreads_yaml}
sell_spreads:
${sell_spreads_yaml}
order_refresh_time: ${order_refresh_time}
order_refresh_tolerance_pct: '${order_refresh_tolerance_pct}' # -1 disables tolerance check (refresh by time logic).
filled_order_delay: ${filled_order_delay} # Wait after a fill before placing a new order at that level.
inventory_skew_enabled: ${inventory_skew_enabled}
target_base_pct: '${target_base_pct}'
inventory_range_multiplier: '${inventory_range_multiplier}' # Skew range multiplier; default 1.0.
price_ceiling: '${price_ceiling}' # Disabled at -1. If set, bot avoids BUY orders when price is at/above this level.
price_floor: '${price_floor}' # Disabled at -1. If set, bot avoids SELL orders when price is at/below this level.
YAML

script_config_filename="$(script_config_filename_for_controller "$config_id")"
script_config_path="${SCRIPT_CONFIG_DIR}/${script_config_filename}"

cat > "$script_config_path" <<YAML
controllers_config:
- ${controller_filename}
script_file_name: v2_with_controllers.py
max_global_drawdown_quote: null
max_controller_drawdown_quote: null
YAML

echo
echo "Config created: $controller_path"
echo "Script config created: $script_config_path"
echo "Quickstart: ./bin/hummingbot_quickstart.py -p a --v2 ${script_config_filename}"
