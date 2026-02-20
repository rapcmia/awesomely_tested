#!/usr/bin/env bash
set -euo pipefail

# README
# 1) Place this script in the root project folder.
# 2) Make it executable once:
#    chmod +x create_market_making_pmm_simple_config.sh
# 3) Run from root:
#    bash create_market_making_pmm_simple_config.sh
#    or
#    ./create_market_making_pmm_simple_config.sh

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
    echo "Please enter an integer."
  done
}

prompt_position_mode() {
  local value
  while true; do
    value="$(prompt_default "position_mode (HEDGE/ONEWAY)" "HEDGE")"
    value="${value^^}"
    case "$value" in
      HEDGE|ONEWAY)
        printf '%s' "$value"
        return
        ;;
      *)
        echo "Please enter HEDGE or ONEWAY."
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

  for file in "${CONTROLLER_CONFIG_DIR}/${date_prefix}"_pmmsimple*.yml; do
    [[ -e "$file" ]] || continue
    base="$(basename "$file" .yml)"
    if [[ "$base" =~ ^${date_prefix}_pmmsimple([0-9]+)$ ]]; then
      num="${BASH_REMATCH[1]}"
      num=$((10#$num))
      (( num > max_n )) && max_n=$num
    fi
  done

  printf '%s_pmmsimple%02d' "$date_prefix" $((max_n + 1))
}

script_config_filename_for_controller() {
  local controller_id="$1"
  local date_prefix="${controller_id%%_*}"
  local suffix="${controller_id#*_}"

  if [[ "$controller_id" == "$suffix" ]]; then
    printf 'conf_market_making_pmm_simple_%s.yml' "$controller_id"
  else
    printf '%s_conf_market_making_pmm_simple_%s.yml' "$date_prefix" "$suffix"
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

csv_to_yaml_decimal_str_list() {
  local csv="$1"
  IFS=',' read -r -a arr <<< "$csv"
  for item in "${arr[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && echo "- '$item'"
  done
}

if [[ ! -d "$CONTROLLER_CONFIG_DIR" ]]; then
  echo "Output directory '$CONTROLLER_CONFIG_DIR' not found."
  exit 1
fi
mkdir -p "$SCRIPT_CONFIG_DIR"

echo "Create market_making.pmm_simple controller config"
echo "------------------------------------------------"
echo "Note: Press Enter to accept the default value shown in [brackets]."
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

total_amount_quote="100"
manual_kill_switch="false"
connector_name="$(prompt_default "connector_name" "binance")"
trading_pair="$(prompt_default "trading_pair" "BTC-FDUSD")"
buy_spreads_csv="0.003"
sell_spreads_csv="0.003"
buy_amounts_pct_csv="1"
sell_amounts_pct_csv="1"
executor_refresh_time="$(prompt_int "executor_refresh_time (seconds)" "60")"
cooldown_time="10"
leverage="10"
position_mode="$(prompt_position_mode)"
stop_loss="0.05"
take_profit="0.0002"
time_limit="300"
take_profit_order_type="$(prompt_int "take_profit_order_type (1=MARKET,2=LIMIT,3=LIMIT_MAKER)" "2")"

buy_spreads_yaml="$(csv_to_yaml_float_list "$buy_spreads_csv")"
sell_spreads_yaml="$(csv_to_yaml_float_list "$sell_spreads_csv")"
buy_amounts_yaml="$(csv_to_yaml_decimal_str_list "$buy_amounts_pct_csv")"
sell_amounts_yaml="$(csv_to_yaml_decimal_str_list "$sell_amounts_pct_csv")"

cat > "$controller_path" <<YAML
id: ${config_id}
controller_name: pmm_simple
controller_type: market_making
total_amount_quote: '${total_amount_quote}'
manual_kill_switch: ${manual_kill_switch}
initial_positions: []
connector_name: ${connector_name}
trading_pair: ${trading_pair}
buy_spreads:
${buy_spreads_yaml}
sell_spreads:
${sell_spreads_yaml}
buy_amounts_pct:
${buy_amounts_yaml}
sell_amounts_pct:
${sell_amounts_yaml}
executor_refresh_time: ${executor_refresh_time}
cooldown_time: ${cooldown_time}
leverage: ${leverage}
position_mode: ${position_mode}
stop_loss: '${stop_loss}'
take_profit: '${take_profit}'
time_limit: ${time_limit}
take_profit_order_type: ${take_profit_order_type}
trailing_stop: null
position_rebalance_threshold_pct: '0.05'
skip_rebalance: true
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
