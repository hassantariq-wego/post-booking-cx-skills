---
name: behavior-trace
description: Show what happened next to every Wego flight booking that ended in a given state over a period, grouped by GDS and by the queue that produced the event, from BigQuery. Use it whenever someone asks how many bookings ended cancelled, failed, failed ticketing or review in process, whether those customers were emailed, or how close to departure it happened. Trigger on "how many bookings", "did they get an email" and "which path did they take" questions about a population, not a single reference.
---

Answer shape: one or two lines that answer the question, the table, one line naming the dataset, one line naming what the data cannot show. Stop there.

## Before running

Run `../_shared/scripts/preflight.sh`. It checks `bq`, the gcloud login and read access to `wego-cloud.integrated_bookings_flights`, and prints the exact command for anything missing. Show that command to the user and stop until they have run it.

## Run

```
../_shared/scripts/query.sh behavior_trace.sql booking_status=CANCELLED cancellation_reason=FAILED_TICKETING payment_status=VOIDED gds= from_shard=20260601 to_shard=20260918 event_from= event_to=
```

Pass an empty value for `cancellation_reason`, `payment_status`, `gds`, `event_from` or `event_to` to mean any. `from_shard`/`to_shard` bound the booking creation date. The runner refuses a missing parameter, so a forgotten filter cannot become a silent NULL.

To check whether a release changed behaviour, bound the state change with `event_from` and leave the shards wide enough to still contain those bookings' creation dates:

```
../_shared/scripts/query.sh behavior_trace.sql booking_status=CANCELLED cancellation_reason=FAILED_TICKETING payment_status=VOIDED gds=TRAVELPORT from_shard=20260601 to_shard=20260924 "event_from=2026-09-23 06:39:27+00" event_to=
```

## Read the result

Each row is one GDS and one combination of queues seen at the moment the booking changed state. The queue number names the code path that acted; read it with the table in `../_shared/references/data-sources.md`. The same end state reached through two different queues is two different pieces of code, and that difference is usually the answer.

The email columns count `EMAIL_LOG` rows, emails handed to wego-crm, before the event and within an hour after it. The reference says what that does and does not prove. The departure columns say how many customers had a flight within a day, within a week, or later.

Treat small rows as noise. A row of 5 bookings does not support a rate.
