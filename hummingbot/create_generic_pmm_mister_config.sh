#!/usr/bin/env bash
set -euo pipefail

# README
# 1) Place this script in the root project folder.
# 2) Make it executable once:
#    chmod +x create_generic_pmm_mister_config.sh
# 3) Run from root:
#    bash create_generic_pmm_mister_config.sh
#    or
#    ./create_generic_pmm_mister_config.sh

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
        echo "Please enter true or false."
        ;;
    esac
  done
}

prompt_position_mode() {
  local value
  while true; do
    value="$(prompt_default "position_mode (HEDGE/ONEWAY)" "ONEWAY")"
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

  for file in "${CONTROLLER_CONFIG_DIR}/${date_prefix}"_pmmmister*.yml; do
    [[ -e "$file" ]] || continue
    base="$(basename "$file" .yml)"
    if [[ "$base" =~ ^${date_prefix}_pmmmister([0-9]+)$ ]]; then
      num="${BASH_REMATCH[1]}"
      num=$((10#$num))
      (( num > max_n )) && max_n=$num
    fi
  done

  printf '%s_pmmmister%02d' "$date_prefix" $((max_n + 1))
}

script_config_filename_for_controller() {
  local controller_id="$1"
  local date_prefix="${controller_id%%_*}"
  local suffix="${controller_id#*_}"

  if [[ "$controller_id" == "$suffix" ]]; then
    printf 'conf_generic_pmm_mister_%s.yml' "$controller_id"
  else
    printf '%s_conf_generic_pmm_mister_%s.yml' "$date_prefix" "$suffix"
  fi
}

if [[ ! -d "$CONTROLLER_CONFIG_DIR" ]]; then
  echo "Output directory '$CONTROLLER_CONFIG_DIR' not found."
  exit 1
fi
mkdir -p "$SCRIPT_CONFIG_DIR"

echo "Create generic.pmm_mister controller config"
echo "------------------------------------------"
echo "Note:"
echo "- Press Enter to accept the default value shown in [brackets]."
echo "- Keep BASE/QUOTE inventory balanced (quote-equivalent)."
echo "- With defaults (total_amount_quote=50, target_base_pct=0.5): BASE 25 / QUOTE 25."
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
total_amount_quote="$(prompt_default "total_amount_quote" "50")"
connector_name="$(prompt_default "connector_name" "kucoin")"
trading_pair="$(prompt_default "trading_pair" "SOL-USDT")"
portfolio_allocation="0.5"
target_base_pct="0.5"
buy_spreads="$(prompt_default "buy_spreads" "0.0005")"
sell_spreads="$(prompt_default "sell_spreads" "0.0005")"
buy_amounts_pct="1"
sell_amounts_pct="1"
executor_refresh_time="$(prompt_int "executor_refresh_time (seconds)" "60")"
position_mode="$(prompt_position_mode)"
position_profit_protection="$(prompt_bool "position_profit_protection" "true")"

# Defaults from baseline entries marked with '#'
manual_kill_switch="false"
min_base_pct="0.3"
max_base_pct="0.6"
buy_position_effectivization_time="120"
sell_position_effectivization_time="120"
buy_cooldown_time="30"
sell_cooldown_time="30"
price_distance_tolerance="0.0005"
refresh_tolerance="0.0005"
tolerance_scaling="1.2"
leverage="10"
take_profit="0.0003"
take_profit_order_type="MARKET"
open_order_type="LIMIT"
max_active_executors_by_level="2"
tick_mode="false"
min_skew="1.0"
global_take_profit="0.01"
global_stop_loss="0.01"

cat > "$controller_path" <<YAML
id: ${config_id}
controller_name: pmm_mister
controller_type: generic
total_amount_quote: '${total_amount_quote}'
manual_kill_switch: ${manual_kill_switch}
initial_positions: []
connector_name: ${connector_name}
trading_pair: ${trading_pair}
portfolio_allocation: '${portfolio_allocation}' # Fraction of total budget used for active orders.
target_base_pct: '${target_base_pct}' # Target base allocation ratio (0.5 = 50% base, 50% quote).
min_base_pct: '${min_base_pct}' # Lower bound of base allocation before strategy prioritizes buys.
max_base_pct: '${max_base_pct}' # Upper bound of base allocation before strategy prioritizes sells.
buy_spreads: '${buy_spreads}'
sell_spreads: '${sell_spreads}'
buy_amounts_pct: '${buy_amounts_pct}' # Buy size weight per level (1 = full single-level weight).
sell_amounts_pct: '${sell_amounts_pct}' # Sell size weight per level (1 = full single-level weight).
executor_refresh_time: ${executor_refresh_time}
buy_cooldown_time: ${buy_cooldown_time} # Wait time before allowing a new buy order on the same side/level.
sell_cooldown_time: ${sell_cooldown_time} # Wait time before allowing a new sell order on the same side/level.
buy_position_effectivization_time: ${buy_position_effectivization_time} # Delay before retiring filled buy executor (keeps position).
sell_position_effectivization_time: ${sell_position_effectivization_time} # Delay before retiring filled sell executor (keeps position).
price_distance_tolerance: '${price_distance_tolerance}' # Minimum gap from current price to place another order.
refresh_tolerance: '${refresh_tolerance}' # Max drift from target-entry before replacing a pending order.
tolerance_scaling: '${tolerance_scaling}' # Multiplier to make deeper levels less strict.
leverage: ${leverage} # Fixed leverage used by this config template.
position_mode: ${position_mode}
take_profit: '${take_profit}' # Per-position take profit target.
take_profit_order_type: ${take_profit_order_type} # TP order type. Options: MARKET, LIMIT, LIMIT_MAKER.
open_order_type: ${open_order_type} # Entry order type. Options: MARKET, LIMIT, LIMIT_MAKER.
max_active_executors_by_level: ${max_active_executors_by_level} # Safety cap for concurrent executors per level.
tick_mode: ${tick_mode} # False = use spread percentages directly (not tick-size mode).
position_profit_protection: ${position_profit_protection}
min_skew: '${min_skew}' # Minimum order-size skew factor (prevents very tiny orders).
global_take_profit: '${global_take_profit}' # Global unrealized PnL take-profit threshold.
global_stop_loss: '${global_stop_loss}' # Global unrealized PnL stop-loss threshold.
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
