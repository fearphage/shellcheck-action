#!/usr/bin/env bash

set -eo pipefail

if [ -z "$GITHUB_TOKEN" ]; then
	>&2 echo "Set the GITHUB_TOKEN env variable."
	exit 1
fi

if [ -z "$GITHUB_SHA" ]; then
	>&2 echo "Set the GITHUB_SHA env variable."
	exit 1
fi

debug() {
  if [ -n "$DEBUG_ACTION" ]; then
    >&2 echo "DEBUG: $1"
  fi
}

parse_json() {
  jq --arg name "$GITHUB_ACTION" --arg now "$(timestamp)" '{
    completed_at: $now,
    conclusion: (if map(select(.level == "error")) | length > 0 then "failure" else "success" end),
    output: {
      title: $name,
      summary: map({level: .level}) | group_by(.level) | map({key: .[0].level, value: length}) | from_entries | "\(.error // 0) error(s) / \(.warning // 0) warning(s) / \(.info // 0) message(s)",
      annotations: map({
        path: .file,
        start_line: .line,
        end_line: .endLine,
        start_column: .column,
        end_column: .endColumn,
        annotation_level: (if .level == "info" then "notice" elif .level == "error" then "failure" else .level end),
        message: .message
      })
    }
  }'
}

request() {
  local method
  local suffix

  if [ -n "$3" ]; then
    method='PATCH'
    suffix="/$3"
  else
    method='POST'
    suffix=''
  fi

  curl \
    --location \
    --show-error \
    --silent \
    --connect-timeout 5 \
    --max-time 5 \
    --request "$method" \
    --header 'Accept: application/vnd.github.antiope-preview+json' \
    --header "Authorization: token ${GITHUB_TOKEN}" \
    --header 'Content-Type: application/json' \
    --header 'User-Agent: github-actions' \
    --data "$2" \
    "${1}/check-runs${suffix}" 2> /dev/null
}

run_shellcheck() {
  (find . -type f -name "*.sh" -exec "shellcheck" "--format=json" {} \;

  for ext in bash sh; do
    grep -iRl "#\!\(/usr/bin/env \|/bin/\)$ext" --exclude-dir ".git" --exclude-dir "node_modules" --exclude "*.txt" --exclude "*.sh" | while read -r file; do
      shellcheck --format=json --shell=$ext "$file"
    done
  done) | jq --slurp flatten
}

timestamp() {
  date +%Y-%m-%dT%H:%M:%SZ
}

main() {
  local id
  local json
  local response
  local results
  local url

  # github doesn't provide this URL so we have to create it
  url="https://api.github.com/repos/$(jq --raw-output .repository.full_name "$GITHUB_EVENT_PATH")"
  json='{"name":"'"${GITHUB_ACTION}"'","status":"in_progress","started_at":"'"$(timestamp)"'","head_sha":"'"${GITHUB_SHA}"'"}'

  # start check
  response="$(request "$url" "$json")"

  debug "checks api response => $response"

  exit 0
  id=$(echo "$response" | jq --raw-output .id)

  if [ -z "$id" ] || [ "$id" = "null" ]; then
    exit 78
  fi

  results="$(run_shellcheck)"

  debug "shellcheck results => $results"

  json=$(echo "$results" | parse_json)

  debug "final json => $json"

  # update check with results
  request "$url" "$json" "$id"

  # failure means errors occurred (warnings are ignored)
  if [ "$(echo "$json" | jq --raw-output .conclusion)" = "failure" ]; then
    exit 1
  fi
}

main "$@"
