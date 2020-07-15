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
  if [ "$DEBUG_ACTION" = "true" ]; then
    >&2 echo "DEBUG: $*"
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
        path: .file | ltrimstr("./"),
        start_line: .line,
        end_line: .endLine,
        annotation_level: (if .level == "info" or .level == "style" then "notice" elif .level == "error" then "failure" else .level end),
        message: .message
      } + (if .line == .endLine then {start_column: .column, end_column: .endColumn} else {} end))
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

  debug "\$1 = $1 ; \$method = $method ; \$suffix = $suffix ; \$data = $2"

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
  (find . -type f \
    \( \
      -name "*.sh" -o \
      -name ".bash*" -o \
      -name ".ksh*" -o \
      -name ".profile*" -o \
      -name ".zlogin*" -o \
      -name ".zlogout*" -o \
      -name ".zprofile*" -o \
      -name ".zsh*" \
    \) \
    -not -path './.git/*' \
    -not -path './node_modules/*' \
    -exec "shellcheck" "--format=json" {} \;

  for ext in bash sh zsh; do
    # shellcheck disable=SC2013
    for file in $(grep -ilr "#\!\(/usr/bin/env \|/bin/\)$ext" --exclude-dir ".git" --exclude-dir "node_modules" --exclude "*.txt" --exclude "*.sh" .); do
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
  local url

  # github doesn't provide this URL so we have to create it
  url="https://api.github.com/repos/$(jq --raw-output .repository.full_name "$GITHUB_EVENT_PATH")"
  json='{"name":"'"${GITHUB_ACTION}"'","status":"in_progress","started_at":"'"$(timestamp)"'","head_sha":"'"${GITHUB_SHA}"'"}'

  # start check
  response="$(request "$url" "$json")"

  id=$(jq --raw-output .id <<< "$response")

  if [ -z "$id" ] || [ "$id" = "null" ]; then
    exit 78
  fi

  json="$(run_shellcheck | parse_json)"

  debug "\$json = $json"

  # update check with results
  request "$url" "$json" "$id"

  debug ".conclusion = $(jq --raw-output .conclusion <<< "$json")"

  if [ "$(jq --raw-output .conclusion <<< "$json")" = "failure" ]; then
    exit 1
  fi
}

main "$@"
