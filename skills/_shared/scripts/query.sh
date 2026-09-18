#!/usr/bin/env bash
# Run one of the bundled SQL files against BigQuery with named parameters.
#
#   query.sh <file.sql> name=value [name=value ...]
#
# Parameter types come from the SQL file's header lines:  -- param: <name> <STRING|INT64|TIMESTAMP>
# Output is CSV on stdout. The bq "Waiting on ..." chatter is suppressed.
set -euo pipefail
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"
PROJECT="wego-cloud"

sql_file="$1"; shift
[ -f "$sql_file" ] || { echo "no such file: $sql_file" >&2; exit 1; }

declare -a params=()
for kv in "$@"; do
  name="${kv%%=*}"; value="${kv#*=}"
  type=$(grep -E "^-- param: $name " "$sql_file" | awk '{print $4}' | head -1)
  [ -n "$type" ] || { echo "unknown parameter '$name' for $sql_file" >&2; exit 1; }
  params+=("--parameter=$name:$type:$value")
done

# Every declared parameter must be supplied; a missing one would silently become NULL.
for declared in $(grep -E "^-- param: " "$sql_file" | awk '{print $3}'); do
  supplied=0
  for kv in "$@"; do [ "${kv%%=*}" = "$declared" ] && supplied=1; done
  [ $supplied -eq 1 ] || { echo "missing parameter '$declared' (see header of $sql_file)" >&2; exit 1; }
done

bq query --project_id="$PROJECT" --use_legacy_sql=false --format=csv --max_rows=500 --quiet \
  "${params[@]}" < "$sql_file" | grep -v '^Waiting on '
