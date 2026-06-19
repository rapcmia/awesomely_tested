ALLOWED_REPO=("hummingbot" "hummingbot-api" "gateway" "condor")

# get the directory and trim the dirname/basename e.g hummingbot/<root base folder>
GET_DIRNAME="$(basename "$(dirname "$PWD")")"
GET_BASENAME="$(basename "$PWD")"
DIRNAME_VALID=false


# prompt usable repos and reassign GET_DIRNAME
prompt_repo() {
  local X Y Z=false

  echo "Available list of hummingbot repo"
  echo "---------------------------------"
  echo "1. hummingbot"
  echo "2. gateway"
  echo "3. hummingbot-api"
  echo "4. condor"
  echo ""

  Y="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' | awk -F/ '{print $2}')"  
  echo -n "Fetching git remote url."; sleep 1;
  echo -n "."; sleep 1;
  echo -n "."; sleep 1;
  echo " found $Y ✅"

  for X in "${ALLOWED_REPO[@]}"; do
    if [[ "$X" == "$Y" ]]; then
      Z=true
      break
    fi
  done

  if [[ "$Z" == true ]]; then
    GET_DIRNAME="$Y"
  else
    echo "$Y is not a valid repo, please check https://github.com/hummingbot ❌"
    exit 1
  fi

}

update_docker_compose_image() {
  local local_image current_image confirm updated_line

  if [[ ! -f "docker-compose.yml" ]]; then
    echo "No docker-compose.yml found in $PWD. Skipping compose image update."
    return 0
  fi

  local_image="hummingbot/$GET_DIRNAME:$GET_BASENAME"
  current_image="$(sed -nE 's/^[[:space:]]*image:[[:space:]]*(.+)$/\1/p' docker-compose.yml | head -n 1)"

  if [[ -z "$current_image" ]]; then
    echo "No image entry found in docker-compose.yml. Skipping compose image update."
    return 0
  fi

  updated_line="$(grep -n -m 1 '^[[:space:]]*image:' docker-compose.yml)"
  if [[ "$current_image" == "$local_image" ]]; then
    echo "docker-compose.yml image was already updated ✅"
    echo "$updated_line"
    return 0
  fi

  echo ""
  read -r -p "Update docker-compose.yml image ($current_image to $local_image) Y/n >> " confirm
  if [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]]; then
    python3 - "$local_image" <<'PY'
from pathlib import Path
import re
import sys

compose_file = Path("docker-compose.yml")
local_image = sys.argv[1]
compose_text = compose_file.read_text()
updated_text, count = re.subn(
    r"(^\s*image:\s*).*$",
    rf"\g<1>{local_image}",
    compose_text,
    count=1,
    flags=re.MULTILINE,
)

if count == 0:
    raise SystemExit(1)

compose_file.write_text(updated_text)
PY
    updated_line="$(grep -n -m 1 '^[[:space:]]*image:' docker-compose.yml)"
    echo "docker-compose.yml image was updated."
    echo "$updated_line"
  else
    echo "docker-compose.yml image was not updated."
  fi
}

build_docker() {
  local DATE_STAMP LOG_FILE COUNT

  DATE_STAMP="$(date +%m%d%Y)"
  LOG_FILE="${DATE_STAMP}_build_${GET_BASENAME}.log"

  COUNT=1
  while [[ -f "$LOG_FILE" ]]; do
    LOG_FILE="${DATE_STAMP}_build_${GET_BASENAME}_${COUNT}.log"
    COUNT=$((COUNT + 1))
  done

  echo ""

  # build docker here
  echo "************************************************************"
  echo ""
  echo "🐳 BUILDING DOCKER IMAGE"
  echo ""
  if docker build -t hummingbot/$GET_DIRNAME:$GET_BASENAME -f Dockerfile . --no-cache 2>&1 | tee -a "$LOG_FILE"; then
    echo ""
    echo "🎉 $(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^hummingbot/$GET_DIRNAME:$GET_BASENAME$")"
    echo ""
    update_docker_compose_image
  else
    echo ""
    echo "Docker failed please check ❌"
    realpath "$LOG_FILE"
  fi
}

for X in "${ALLOWED_REPO[@]}"; do 
  if [[ "$X" == "$GET_DIRNAME" ]]; then
    DIRNAME_VALID=true
    break
  fi
done

if [[ "$DIRNAME_VALID" == true ]]; then 
  echo ""
  echo -n "Validating."; sleep 0.5
  echo -n "."; sleep 0.5
  echo -n "."; sleep 0.5
  echo " $GET_DIRNAME/$GET_BASENAME ✅"
else
  echo "Not a valid repo, $GET_DIRNAME/$GET_BASENAME ❌"
  echo ""
  prompt_repo
fi

echo -n "This setup will build docker hummingbot/$GET_DIRNAME:$GET_BASENAME"; sleep 1.5
echo ""
build_docker
