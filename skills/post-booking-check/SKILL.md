---
name: post-booking-check
description: Answer a post-booking question about Wego flight bookings with a table of facts from BigQuery, not a story. Use it whenever someone gives a WF booking reference and asks what happened to it, asks what happened to the bookings that ended in some state (cancelled, failed ticketing, review in process) over a period, or asks whether a release or PR in wego-fares, flight-integrations, roxana, olympias, orchard or wego-ai changed post-booking outcomes. Trigger on CS escalations carrying a booking reference, on "did the customer get an email", on "how many bookings", and on "did the deploy change anything", even when BigQuery is not mentioned.
---

Three paths, one rule: return what the data says as a table, name the source of each column, name what is unverified, and stop. Add narrative only when asked.

## Before any path

Run `scripts/preflight.sh`. It checks `bq`, the gcloud login and read access to `wego-cloud.integrated_bookings_flights`, and prints the exact command for anything missing. Show that command to the user and stop until they have run it. Do not attempt the login yourself: it needs a browser round-trip in the user's own terminal.

Run queries only through `scripts/query.sh <sql> name=value ...`. It types the named parameters from the SQL header and refuses to run with one missing, which is what stops a silent NULL filter from returning a confident wrong answer.

## Path 1: booking-trace

Input: one booking reference. Output: every recorded event for it, in UTC order.

```
scripts/query.sh sql/booking_trace.sql ref=WF... from_shard=YYYYMMDD to_shard=YYYYMMDD
```

The shards bound every sharded table by date. If you do not know when the booking was created, start with the last 90 days; if the created row is missing, widen. Once you have the created date, 45 days after it is enough.

Present the timeline as returned. It already collapses repeated polling into one row. Then answer the question that was asked in one or two lines above the table, for example "cancelled by the Travelport sweep at 16:51 UTC, no email after the cancel". The `EMAIL_LOG` rows are emails handed to wego-crm; see `references/data-sources.md` for what that does and does not prove.

## Path 2: behavior-trace

Input: a booking state and a window. Output: what happened next to every booking in that state, grouped by GDS and by the queue that produced the event.

```
scripts/query.sh sql/behavior_trace.sql booking_status=CANCELLED cancellation_reason=FAILED_TICKETING payment_status=VOIDED gds= from_shard=20260601 to_shard=20260918
```

Pass `''` (an empty value) for `cancellation_reason`, `payment_status` or `gds` to mean any. The window bounds the booking creation date. The columns tell you which code path acted (queue number), whether the customer was told before and after (email counts), and how close the flight was.

Read the queue numbers with `references/data-sources.md`; the same end state reached through different queues is different code, and that difference is usually the answer.

## Path 3: release-impact

Input: a repo, a release tag or PR, and a window in days. Output: post-booking outcomes for bookings created in the N days before the release versus the N days after, per GDS plus an ALL row.

First resolve the release time in UTC from the repo, never from memory:

```
git -C <repo> log -1 --format=%cI <tag>            # wego-fares tags look like 2026.09.08.02.master
gh pr view <n> --repo wego/<repo> --json mergedAt   # for a PR
```

Then:

```
scripts/query.sh sql/release_impact.sql "at=2026-09-08 06:17:16" days=7 gds= from_shard=20260901 to_shard=20260915
```

`from_shard` and `to_shard` must cover the whole before-and-after span. The query counts only bookings where money moved, so abandoned checkouts and card declines do not dilute the rates.

The metrics are booking outcomes, so they answer for wego-fares and flight-integrations releases. For roxana, olympias, orchard and wego-ai the release time resolves the same way but these tables cannot see the change; say "metrics for this repo are not defined yet" rather than running the query and implying it measured something.

Show the ALL row and the GDS rows with enough volume to matter. Flag a delta only when both periods have the volume to support it; a change from 3 to 6 bookings is noise, say so.

## When BigQuery cannot settle it

BigQuery mirrors the wego-fares database and its outbound-call log. It cannot show application exceptions, whether wego-crm delivered an email, or the customer's own actions on My Trips. Say which of those the question needs and stop, or, if the user has Datadog connected, pull the app log for the booking reference and the minute in question. Do not guess across the gap.
