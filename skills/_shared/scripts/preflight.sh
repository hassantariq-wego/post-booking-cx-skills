#!/usr/bin/env bash
# Verify everything post-booking-check needs, and print the exact fix for anything missing.
# Exit 0 = ready. Exit 1 = something to fix (already printed).
set -u

# Find the Cloud SDK without assuming one machine's layout.
if ! command -v bq >/dev/null 2>&1; then
  for d in /opt/homebrew/share/google-cloud-sdk/bin /usr/local/share/google-cloud-sdk/bin \
           "$HOME/google-cloud-sdk/bin" /usr/lib/google-cloud-sdk/bin /snap/bin; do
    if [ -x "$d/bq" ]; then PATH="$d:$PATH"; break; fi
  done
  export PATH
fi

PROJECT="wego-cloud"
ok=1
account=""

if ! command -v bq >/dev/null 2>&1; then
  echo "MISSING bq. Install the Google Cloud SDK:  brew install --cask google-cloud-sdk"
  ok=0
fi

if [ $ok -eq 1 ]; then
  account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
  if [ -z "$account" ]; then
    echo "NOT LOGGED IN. In a separate terminal (not through the ! prompt, the OAuth callback dies if interrupted):"
    echo "  gcloud auth login --update-adc"
    ok=0
  else
    echo "gcloud: $account"
  fi
fi

if [ $ok -eq 1 ]; then
  # An expired credential still lists as ACTIVE above, so this check is where a lapsed login
  # surfaces. Read the error before blaming permissions: the two need different people.
  err=$(bq query --project_id="$PROJECT" --use_legacy_sql=false --dry_run --quiet \
        "SELECT 1 FROM \`$PROJECT.integrated_bookings_flights.queue_events\` LIMIT 1" 2>&1 >/dev/null)
  if [ $? -ne 0 ]; then
    if printf '%s' "$err" | grep -qiE 'reauthentication|invalid_grant|refreshing your current auth|re-?authenticate|credentials have expired'; then
      echo "LOGIN EXPIRED, not an access problem. In a separate terminal (not through the ! prompt):"
      echo "  gcloud auth login --update-adc"
    elif printf '%s' "$err" | grep -qiE 'permission|access denied|not authorized|forbidden|404|not found'; then
      echo "NO ACCESS to $PROJECT.integrated_bookings_flights with $account. Ask IT Ops for BigQuery read access to wego-cloud."
    else
      echo "BIGQUERY CHECK FAILED with $account, cause not recognised. Raw error:"
      printf '%s\n' "$err" | head -5 | sed 's/^/  /'
    fi
    ok=0
  else
    echo "bigquery: $PROJECT.integrated_bookings_flights readable"
  fi
fi

[ $ok -eq 1 ] && echo "ready" && exit 0
exit 1
