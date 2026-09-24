---
name: release-impact
description: Compare post-booking outcomes for Wego flight bookings created in the days before a release with the days after it, per GDS plus an all-GDS row, from BigQuery. Use it whenever someone asks whether a release, deploy or merged PR in wego-fares, flight-integrations, roxana, olympias, orchard or wego-ai changed ticketing rates, failures, cancellations, customer emails or time to ticket. Trigger on "did the deploy change anything" and "check the impact of the release" even when BigQuery is not mentioned.
---

Answer shape: one or two lines that answer the question, the table, one line naming the dataset, one line naming what the data cannot show. Stop there.

## Before running

Run `../_shared/scripts/preflight.sh`. It checks `bq`, the gcloud login and read access to `wego-cloud.integrated_bookings_flights`, and prints the exact command for anything missing. Show that command to the user and stop until they have run it.

## Resolve the release time

From the repo, never from memory, in UTC:

```
git -C <repo> log -1 --format=%cI <tag>            # wego-fares tags look like 2026.09.08.02.master
gh pr view <n> --repo wego/<repo> --json mergedAt   # for a PR
```

Both give the time the code reached master, which is earlier than the time production started
running it, by the build plus the rolling deploy. Over a window of days that gap is noise. On a
same-day check it puts old-code bookings on the new-code side, so use the time the new version
first served instead: the Datadog deployment change story for the service, or the deploy job's
completion time. Say in the answer which one you used.

Several tags can ship on one day, so "the 23 Sep release" may be ambiguous. Name the tag, and say
which change is being measured and which other tags share the window.

The metrics are booking outcomes, so they answer for wego-fares and flight-integrations releases. For roxana, olympias, orchard and wego-ai the release time resolves the same way but these tables cannot see the change. Say "metrics for this repo are not defined yet" rather than running the query and implying it measured something.

## Run

```
../_shared/scripts/query.sh release_impact.sql "at=2026-09-08 06:17:16" days=7 gds= from_shard=20260901 to_shard=20260915 | python3 ../_shared/scripts/render.py
```

`from_shard` and `to_shard` must cover the whole before-and-after span. Pass an empty `gds` to mean any. The query counts only bookings where money moved, so abandoned checkouts and card declines do not dilute the rates.

## Read the result

Show the ALL row and the GDS rows with enough volume to matter. Flag a delta only when both periods have the volume to support it; a change from 3 to 6 bookings is noise, say so.

`of_which_emailed` counts cancels with a customer email within an hour of `cancelled_at`. `of_which_no_cancel_time` counts cancels that carry no `cancelled_at` at all; their email coverage cannot be measured, so report them separately rather than folding them into a rate.
