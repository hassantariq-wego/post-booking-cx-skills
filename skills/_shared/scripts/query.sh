#!/usr/bin/env bash
# Run one of the bundled SQL files against BigQuery with named parameters.
#
#   query.sh <file.sql> name=value [name=value ...]
#
# Parameter types come from the SQL file's header lines:  -- param: <name> <STRING|INT64|TIMESTAMP>
# Output is CSV on stdout. The bq "Waiting on ..." chatter is suppressed.
#
# Exit 0 means the query ran, including when it matched nothing: an empty result is an
# answer, not a failure, and says so on stderr. Exit 1 always carries a message saying why.
set -euo pipefail

# Find the Cloud SDK without assuming one machine's layout.
if ! command -v bq >/dev/null 2>&1; then
  for d in /opt/homebrew/share/google-cloud-sdk/bin /usr/local/share/google-cloud-sdk/bin \
           "$HOME/google-cloud-sdk/bin" /usr/lib/google-cloud-sdk/bin /snap/bin; do
    if [ -x "$d/bq" ]; then PATH="$d:$PATH"; break; fi
  done
  export PATH
fi
command -v bq >/dev/null 2>&1 || {
  echo "bq not found. Install the Google Cloud SDK, or add its bin directory to PATH." >&2; exit 1; }

PROJECT="wego-cloud"
MAX_ROWS=500

[ $# -ge 1 ] || { echo "usage: query.sh <file.sql> name=value [name=value ...]" >&2; exit 1; }
sql_file="$1"; shift
[ -f "$sql_file" ] || { echo "no such file: $sql_file" >&2; exit 1; }

declare -a params=()
for kv in "$@"; do
  case "$kv" in
    *=*) ;;
    *) echo "argument '$kv' is not name=value" >&2; exit 1 ;;
  esac
  name="${kv%%=*}"; value="${kv#*=}"
  # '|| true' matters: under 'set -e' a non-matching grep would abort here, before the
  # check below could name the offending parameter, leaving the caller with silent exit 1.
  type=$(grep -E "^-- param: $name " "$sql_file" | awk '{print $4}' | head -1 || true)
  [ -n "$type" ] || {
    echo "unknown parameter '$name' for $sql_file. Declared parameters:" >&2
    grep -E "^-- param: " "$sql_file" | awk '{print "  " $3 " (" $4 ")"}' >&2
    exit 1; }
  params+=("--parameter=$name:$type:$value")
done

# Every declared parameter must be supplied; a missing one would silently become NULL.
for declared in $(grep -E "^-- param: " "$sql_file" | awk '{print $3}'); do
  supplied=0
  for kv in "$@"; do if [ "${kv%%=*}" = "$declared" ]; then supplied=1; fi; done
  [ $supplied -eq 1 ] || { echo "missing parameter '$declared' (see header of $sql_file)" >&2; exit 1; }
done

raw=$(mktemp); err=$(mktemp)
trap 'rm -f "$raw" "$err"' EXIT

if ! bq query --project_id="$PROJECT" --use_legacy_sql=false --format=csv \
       --max_rows="$MAX_ROWS" --quiet "${params[@]}" < "$sql_file" >"$raw" 2>"$err"; then
  echo "BigQuery query failed:" >&2
  head -20 "$err" >&2
  exit 1
fi

grep -v '^Waiting on ' <"$raw" || true

# A CSV result is one header line plus one line per row.
lines=$(wc -l <"$raw" | tr -d ' ')
rows=$(( lines > 0 ? lines - 1 : 0 ))
if [ "$rows" -eq 0 ]; then
  echo "no rows matched. The query ran successfully; this is an answer, not an error." >&2
elif [ "$rows" -ge "$MAX_ROWS" ]; then
  echo "WARNING: hit the ${MAX_ROWS}-row cap, so this result is probably truncated. Narrow the filters." >&2
fi
