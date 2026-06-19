#!/usr/bin/env bash
set -euo pipefail

TARGET="AGENTS.md"

if [[ -e "$TARGET" ]]; then
  n=1
  while [[ -e "AGENTS${n}.md" ]]; do
    ((n++))
  done
  mv "$TARGET" "AGENTS${n}.md"
fi

cat > "$TARGET" <<'CONTENT'
# AGENTS.md

# AGENTS.md

# AGENTS.md

<INSTRUCTIONS>
## This is the main instruction 
Whenever we start the session, always check if a log file is created. The log file must have a prefix of today's date MMDDYYYY.log
- Strictly no adding or modifying of codebase
- Use HTTP routes only by default for all tests and operations
- ALL activities, executions, checks, and troubleshooting must start by checking the relevant Hummingbot API route or Gateway route first before any other method is used
- Prefer the standard app/API route flow first:
  - Hummingbot API routes on `http://localhost:8000/...`
  - Gateway/Fastify routes on `http://localhost:15888/...` only when the task is explicitly about Gateway routes or Gateway-native config/status checks
  - Condor routes on `http://localhost:8088/...` when the task is explicitly about `hummingbot/condor`
- Before starting any test, always check the relevant image in `docker-compose.yml`
- If the current work is based on a non-`latest` root base such as `hummingbot/hummingbot-api:test`, `hummingbot/gateway:test`, or `hummingbot/condor:test`, verify whether `docker-compose.yml` is using the same image tag
- If the root base folder/context and the image in `docker-compose.yml` do not match, check whether a local Docker image exists that matches the root base name/tag being tested
- If that matching local image exists, propose updating `docker-compose.yml` to use that image and tell the user which image will be used
- The user must validate and explicitly confirm the image correction before any other test execution continues
- Do not continue with the rest of the test if there is an image mismatch that has not been confirmed by the user
- Every test and activity must align with route-first validation; check the relevant `http://localhost:8000/...` Hummingbot API flow first when the task is API-app-facing, check the relevant `http://localhost:15888/...` Gateway flow first when the task is explicitly Gateway-facing, or check the relevant `http://localhost:8088/...` Condor flow first when the task is explicitly Condor-facing
- Requests that mention a Gateway version, tag, or image such as `620`, `latest`, or `development` must be interpreted first as a route/version target for Gateway validation, not as implicit approval to use manual Docker commands
- Only after the relevant Hummingbot API or Gateway route flow is checked and found insufficient may any non-route path be considered, and only after the user confirms it is okay to move forward outside the route flow
- Do not use manual Docker commands, direct database queries, filesystem inspection, or other non-route methods unless the user explicitly asks for it or approves it first
- Even when the user asks to "start" or "use" a specific Gateway image/version, do not assume manual Docker lifecycle commands are authorized unless the user explicitly asks for Docker/container actions
- Read-only Postgres queries are allowed as an exception when the task is specifically to verify persistence or database state (for example `orders`, `trades`, `executors`, or reconciliation issues); never use write/update/delete DB operations
- If a task requires any non-standard path or non-route method, ask the user first so the alternate path can be verified before proceeding
- If no log file, create one MMDDYYYY.log
- Test must be using curl endpoints all the time and formatted by jq
- All secrets must be masked with XXX when added to logs (api keys, private keys, auth password, passphrases)
- Always add to the last line of the log file the curl route tests
- For port 8000 auth, always check `.env` first by running `cat .env`; use `USERNAME` and `PASSWORD` from that file and never assume `admin:admin`
- For any unauthorized/401 response on port 8000 routes, check `.env` again with `cat .env` before retrying
- If `.env` is missing or the auth fields are unclear, ask the user
- If running on a VPS/remote/headless host and localhost curl fails, retry with the server's public IP on the same port
- When recording the public IP in logs, mask the non-leading octets (e.g., `139-xx-xx`) instead of the full IP
- Always display curl/jq results in the chat; if the output is too long, trim it and clearly note that the full response is in the log file
- Add a blank line between curl tests in the log file
- Dont start gateway unless needed, ask permission first
	#### route description
	curl .... | jq
	{response}
	logs: <single related line from hummingbot-api or gateway logs, or fallback text>
- For curl commands with JSON payloads, always use multiline body formatting:
	curl ... -H "Content-Type: application/json" -d '
	{
	  ...
	}' | jq
- For gateway trade route tests that require token amounts, always use `3 USD equivalent` for both base and quote sides (do not assume token amount = 3; convert per current price/quote).
- For all LP tests that execute `open-position` or `add-liquidity`, always get the latest `pool-info` price first, then set dynamic bounds from that live price:
  - `lowerPrice = current_price * 0.995`
  - `upperPrice = current_price * 1.005`
  (use this instead of fixed 1% bands).
- Keep route labels descriptive and consistent (e.g., `#### deploy lp executor`, `#### verify gateway status`)
- For long responses in log, concise/trimmed structured summaries are allowed (same style used in 02162026.log), but must keep key fields needed for troubleshooting.
- For curl routes that failed or error on response, always check if there is a error response from gateway or hummingbot-api logs from the curl route tests and append to the template.
	- if no log file to check, just add something like "not found related error on logs"
- If a curl fails, review the current `MMDDYYYY.log` for any prior successful attempts of the same route (host, auth, payload) and reuse that info on the retry; mention this review in the log entry.
- For successful curl tests, append a logs line that only tracks the route used (from hummingbot-api or gateway logs)
	- Sample:
		#### route
		curl .... | jq
		{response}
		logs: 2025-12-19 09:18:51,790 - services.accounts_service - WARNING - No cached price available for HYPE-USD, using 0
</INSTRUCTIONS>
CONTENT
