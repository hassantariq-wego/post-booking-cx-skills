---
name: booking-trace
description: Show what happened to one Wego flight booking as a table of every recorded event in UTC order, from BigQuery. Use it whenever someone gives a WF booking reference and asks what happened, why it was cancelled or failed, whether the customer was emailed, or which system acted on it. Trigger on CS escalations carrying a booking reference even when BigQuery is not mentioned.
---

Answer shape: one or two lines that answer the question, the table, one line naming the dataset, one line naming what the data cannot show. Stop there. The reader is a PM or a CS lead who will ask if they want more.

## Before running

Run `../_shared/scripts/preflight.sh`. It checks `bq`, the gcloud login and read access to `wego-cloud.integrated_bookings_flights`, and prints the exact command for anything missing. Show that command to the user and stop until they have run it; the login needs a browser round-trip in their own terminal.

## Run

```
../_shared/scripts/query.sh booking_trace.sql ref=WF... from_shard=YYYYMMDD to_shard=YYYYMMDD | python3 ../_shared/scripts/render.py
```

The runner types the named parameters from the SQL header and refuses to run with one missing, which is what stops a forgotten filter from returning a confident wrong answer.

The shards bound every sharded table by date. Created date to 45 days after it is enough. If you only know the month, use its first day to 45 days past its end. If you know nothing, start with the last 90 days and widen if the created row is missing.

## Read the result

Present the timeline as returned. It already collapses repeated polling into one row. The first row has no timestamp: it is the itinerary's current state, not an event, so keep it as the header of the table.

Two things need `../_shared/references/data-sources.md` to read correctly: the queue number of the event that changed the booking names the code path that acted, and its table says which paths email the customer; and an `EMAIL_LOG` row is an email handed to wego-crm, which proves less than it looks.

BigQuery cannot show application exceptions, whether wego-crm delivered an email, or what the customer did on My Trips. Name the one the question needs and stop; do not guess across the gap.
