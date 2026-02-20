#!/usr/bin/env bash
set -euo pipefail

# README
# 1) Place this script in the root project folder.
# 2) Make it executable once:
#    chmod +x create_directional_bollinger_v1_config.sh
# 3) Run from root:
#    bash create_directional_bollinger_v1_config.sh
#    or
#    ./create_directional_bollinger_v1_config.sh

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

  for file in "${CONTROLLER_CONFIG_DIR}/${date_prefix}"_bollingerv1_*.yml; do
    [[ -e "$file" ]] || continue
    base="$(basename "$file" .yml)"
    if [[ "$base" =~ ^${date_prefix}_bollingerv1_([0-9]+)$ ]]; then
      num="${BASH_REMATCH[1]}"
      num=$((10#$num))
      (( num > max_n )) && max_n=$num
    fi
  done

  printf '%s_bollingerv1_%02d' "$date_prefix" $((max_n + 1))
}

script_config_filename_for_controller() {
  local controller_id="$1"
  local date_prefix="${controller_id%%_*}"
  local suffix="${controller_id#*_}"

  if [[ "$controller_id" == "$suffix" ]]; then
    printf 'conf_directional_bollinger_v1_%s.yml' "$controller_id"
  else
    printf '%s_conf_directional_bollinger_v1_%s.yml' "$date_prefix" "$suffix"
  fi
}

if [[ ! -d "$CONTROLLER_CONFIG_DIR" ]]; then
  echo "Output directory '$CONTROLLER_CONFIG_DIR' not found."
  exit 1
fi
mkdir -p "$SCRIPT_CONFIG_DIR"

echo "Create directional.bollinger_v1 controller config"
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

total_amount_quote="$(prompt_default "total_amount_quote" "30")"
manual_kill_switch="false"
connector_name="$(prompt_default "connector_name" "binance_perpetual")"
trading_pair="$(prompt_default "trading_pair" "SOL-USDT")"
candles_connector="${connector_name}"
candles_trading_pair="${trading_pair}"
echo "candles_data: ${candles_connector}, ${candles_trading_pair}"
max_executors_per_side="2"
cooldown_time="$(prompt_int "cooldown_time (seconds)" "30")"
leverage="10"
position_mode="HEDGE"
stop_loss="0.01"
take_profit="$(prompt_default "take_profit" "0.0003")"
time_limit="300"
take_profit_order_type="1"
trailing_stop="null"
interval="3m"
bb_length="200"
bb_std="2.0"
bb_long_threshold="$(prompt_default "bb_long_threshold" "0.3")"
bb_short_threshold="$(prompt_default "bb_short_threshold" "0.7")"

cat > "$controller_path" <<YAML
id: ${config_id}
controller_name: bollinger_v1
controller_type: directional_trading
total_amount_quote: '${total_amount_quote}'
manual_kill_switch: ${manual_kill_switch}
initial_positions: []
connector_name: ${connector_name}
trading_pair: ${trading_pair}
max_executors_per_side: ${max_executors_per_side}
cooldown_time: ${cooldown_time}
leverage: ${leverage}
position_mode: ${position_mode}
stop_loss: '${stop_loss}'
take_profit: '${take_profit}'
time_limit: ${time_limit}
take_profit_order_type: ${take_profit_order_type}
trailing_stop: ${trailing_stop}
candles_connector: ${candles_connector}
candles_trading_pair: ${candles_trading_pair}
interval: ${interval}
bb_length: ${bb_length}
bb_std: ${bb_std}
bb_long_threshold: ${bb_long_threshold}
bb_short_threshold: ${bb_short_threshold}
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
