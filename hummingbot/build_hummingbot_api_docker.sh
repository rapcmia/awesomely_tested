#!/usr/bin/env bash

set -euo pipefail

ROOT="$PWD"
MODE="build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revert)
      MODE="revert"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--revert]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$ROOT/Dockerfile" || ! -f "$ROOT/docker-compose.yml" || ! -f "$ROOT/environment.yml" ]]; then
  echo "Could not find hummingbot-api project files in the current directory: $ROOT" >&2
  echo "Run this script while your shell is inside the hummingbot-api project folder." >&2
  exit 1
fi

TAG="$(basename "$ROOT")"
LOG_FILE="$ROOT/$(date +%d%m%Y)_hummingbot-api_docker_build.log"
cd "$ROOT"

if [[ "$MODE" == "revert" ]]; then
  python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
dockerfile = root / "Dockerfile"
compose = root / "docker-compose.yml"
env_file = root / "environment.yml"

docker_text = dockerfile.read_text()
docker_text = docker_text.replace("COPY *.whl .\n", "", 1)
dockerfile.write_text(docker_text)

compose_text = compose.read_text()
compose_text = re.sub(
    r"(^\s*image:\s*hummingbot/hummingbot-api:).*$",
    r"\g<1>latest",
    compose_text,
    count=1,
    flags=re.MULTILINE,
)
compose.write_text(compose_text)

env_lines = env_file.read_text().splitlines()
wheel_index = next(
    (i for i, line in enumerate(env_lines) if ".whl" in line and line.lstrip().startswith("- ")),
    None,
)

if wheel_index is not None:
    del env_lines[wheel_index]

comment_index = next(
    (i for i, line in enumerate(env_lines) if line.strip() == "# hummingbot"),
    None,
)

if comment_index is not None:
    env_lines[comment_index] = env_lines[comment_index].replace("# hummingbot", "- hummingbot", 1)
elif not any(line.strip() == "- hummingbot" for line in env_lines):
    pip_index = next((i for i, line in enumerate(env_lines) if line.strip() == "- pip:"), None)
    if pip_index is not None:
        env_lines.insert(pip_index + 1, "      - hummingbot")

env_file.write_text("\n".join(env_lines) + "\n")
PY

  echo
  echo "Reverted to default setup"
  echo "- Dockerfile no longer contains COPY *.whl ."
  echo "- docker-compose.yml image set to hummingbot/hummingbot-api:latest"
  echo "- environment.yml restored to - hummingbot"
  exit 0
fi

prep_output="$(python3 - "$ROOT" "$TAG" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
tag = sys.argv[2]

dockerfile = root / "Dockerfile"
compose = root / "docker-compose.yml"
env_file = root / "environment.yml"

docker_text = dockerfile.read_text()
if "COPY *.whl ." not in docker_text:
    docker_text = docker_text.replace("COPY environment.yml .", "COPY environment.yml .\nCOPY *.whl .", 1)
    dockerfile.write_text(docker_text)

compose_text = compose.read_text()
compose_text = re.sub(
    r"(^\s*image:\s*hummingbot/hummingbot-api:).*$",
    rf"\g<1>{tag}",
    compose_text,
    count=1,
    flags=re.MULTILINE,
)
compose.write_text(compose_text)

image_match = re.search(
    r"^\s*image:\s*(hummingbot/hummingbot-api:[^\s]+)\s*$",
    compose_text,
    flags=re.MULTILINE,
)
image_name = image_match.group(1) if image_match else f"hummingbot/hummingbot-api:{tag}"

wheels = sorted(root.glob("*.whl"))
wheel = wheels[0] if wheels else None
env_text = env_file.read_text()
env_updated = False
wheel_present = wheel is not None
wheel_message = f"Found {wheel.name} in repo root." if wheel else "No .whl file found in repo root."
env_ready = True
env_message = "environment.yml left unchanged because no .whl file was found."

if wheel and ".whl" in env_text:
    wheel_line = next((line.strip() for line in env_text.splitlines() if ".whl" in line), "")
    if wheel.name in env_text:
        env_message = f"environment.yml already points to {wheel.name}."
    else:
        env_ready = False
        env_message = f"environment.yml already has another wheel entry: {wheel_line}"
elif wheel and "- hummingbot" in env_text:
    env_text = env_text.replace("- hummingbot", "# hummingbot\n      - " + wheel.name, 1)
    env_file.write_text(env_text)
    env_updated = True
    env_message = f"Added {wheel.name} to environment.yml."
elif wheel:
    env_ready = False
    env_message = "Could not find '- hummingbot' in environment.yml."

docker_ready = "COPY *.whl ." in dockerfile.read_text()
compose_ready = image_name == f"hummingbot/hummingbot-api:{tag}"

print(f"IMAGE_NAME={image_name}")
print(f"CHECK_DOCKERFILE={'OK' if docker_ready else 'FAIL'}")
print("CHECK_DOCKERFILE_MSG=Dockerfile includes COPY *.whl .")
print(f"CHECK_WHEEL_FILE={'OK' if wheel_present else 'FAIL'}")
print(f"CHECK_WHEEL_FILE_MSG={wheel_message}")
print(f"CHECK_ENV={'OK' if env_ready else 'FAIL'}")
print(f"CHECK_ENV_MSG={env_message}")
print(f"CHECK_COMPOSE={'OK' if compose_ready else 'FAIL'}")
print(f"CHECK_COMPOSE_MSG=docker-compose.yml image set to {image_name}")
print(f"ENV_UPDATED={'YES' if env_updated else 'NO'}")
PY
)"

IMAGE_NAME=""
CHECK_DOCKERFILE=""
CHECK_DOCKERFILE_MSG=""
CHECK_WHEEL_FILE=""
CHECK_WHEEL_FILE_MSG=""
CHECK_ENV=""
CHECK_ENV_MSG=""
CHECK_COMPOSE=""
CHECK_COMPOSE_MSG=""
ENV_UPDATED=""

while IFS='=' read -r key value; do
  case "$key" in
    IMAGE_NAME) IMAGE_NAME="$value" ;;
    CHECK_DOCKERFILE) CHECK_DOCKERFILE="$value" ;;
    CHECK_DOCKERFILE_MSG) CHECK_DOCKERFILE_MSG="$value" ;;
    CHECK_WHEEL_FILE) CHECK_WHEEL_FILE="$value" ;;
    CHECK_WHEEL_FILE_MSG) CHECK_WHEEL_FILE_MSG="$value" ;;
    CHECK_ENV) CHECK_ENV="$value" ;;
    CHECK_ENV_MSG) CHECK_ENV_MSG="$value" ;;
    CHECK_COMPOSE) CHECK_COMPOSE="$value" ;;
    CHECK_COMPOSE_MSG) CHECK_COMPOSE_MSG="$value" ;;
    ENV_UPDATED) ENV_UPDATED="$value" ;;
  esac
done <<< "$prep_output"

status_label() {
  if [[ "$1" == "OK" ]]; then
    printf 'ok'
  else
    printf 'fail'
  fi
}

echo
echo "Docker build checklist"
echo "- [$(status_label "$CHECK_DOCKERFILE")] $CHECK_DOCKERFILE_MSG"
echo "- [$(status_label "$CHECK_WHEEL_FILE")] $CHECK_WHEEL_FILE_MSG"
echo "- [$(status_label "$CHECK_ENV")] $CHECK_ENV_MSG"
echo "- [$(status_label "$CHECK_COMPOSE")] $CHECK_COMPOSE_MSG"

if [[ "$ENV_UPDATED" == "YES" ]]; then
  echo "environment.yml was updated for the current .whl file."
fi

if [[ "$CHECK_DOCKERFILE" != "OK" || "$CHECK_WHEEL_FILE" != "OK" || "$CHECK_ENV" != "OK" || "$CHECK_COMPOSE" != "OK" ]]; then
  echo
  echo "Build skipped because the checklist is not complete."
  exit 1
fi

echo
read -r -p "Build the image now? [Y/n] >> " confirm
if [[ -n "$confirm" && ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Build cancelled."
  exit 0
fi

echo "Building Docker image: $IMAGE_NAME"
echo "Build log: $LOG_FILE"

docker build -t "$IMAGE_NAME" -f Dockerfile . --no-cache 2>&1 | tee "$LOG_FILE"
