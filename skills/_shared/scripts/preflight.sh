#!/usr/bin/env bash
# Verify everything post-booking-check needs, and print the exact fix for anything missing.
# Exit 0 = ready. Exit 1 = something to fix (already printed).
set -u
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"
PROJECT="wego-cloud"
ok=1

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
  if ! bq query --project_id="$PROJECT" --use_legacy_sql=false --dry_run --quiet \
      "SELECT 1 FROM \`$PROJECT.integrated_bookings_flights.queue_events\` LIMIT 1" >/dev/null 2>&1; then
    echo "NO ACCESS to $PROJECT.integrated_bookings_flights with $account. Ask IT Ops for BigQuery read access to wego-cloud."
    ok=0
  else
    echo "bigquery: $PROJECT.integrated_bookings_flights readable"
  fi
fi

[ $ok -eq 1 ] && echo "ready" && exit 0
exit 1
