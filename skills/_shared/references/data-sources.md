# Data sources

Everything runs against `wego-cloud.integrated_bookings_flights` in BigQuery, a mirror of the wego-fares production database plus wego-fares's own outbound-call log. Read with `bq`, project `wego-cloud`.

## Tables the queries use

| Table | Grain | Sharded by | Notes |
|---|---|---|---|
| `bookings*` | one booking | created date | `booking_status`, `payment_status`, `cancellation_reason`, `created_at`, `cancelled_at`, `completed_at` (ticketed time), `booking_type` (SS, SOO, M), `booking_mode` |
| `itineraries*` | one itinerary | created date | `integration_type` is the GDS or LCC (SABRE, TRAVELPORT, ATLAS...), `gds_ref` is the PNR, `ticket_status`, `qct_status` |
| `payments*` | one payment attempt | created date | join on `order_id = bookings.payment_order_id`; `payment_method_code` |
| `legs*` | one flight leg | created date | `scd_dep_date_time_utc` gives departure |
| `queue_events` | one GDS queue event | not sharded | `queue_number`, `status`, `created_at`; join on `booking_id` |
| `booking_admin_notes` | one back-office note | not sharded | join on `booking_id` |
| `provider_exchange_logs*` | one outbound HTTP call by wego-fares | request date | `type`, `status` (HTTP), `requested_at`, `wego_ref` |

Shard suffixes are `YYYYMMDD`. Always bound them with `_TABLE_SUFFIX BETWEEN`; an unbounded scan of `provider_exchange_logs*` costs tens of gigabytes.

## Front-end tracking: `wego-cloud.services_genzo`

What a visitor did on My Trips. Used by release-impact for roxana, olympias and orchard releases.

| Table | Grain | Sharded by | Notes |
|---|---|---|---|
| `pages_views*` | one page view | Singapore date | booking-details page is `page.sub_type = 'flight_booking_history_details'`; `page.url` carries the `WF...` ref; `device.app` is `WEB_APP` (roxana), `MOBILE_WEB_APP` (olympias), `IOS_APP` / `ANDROID_APP` and tablet variants (the orchard miniapp) |
| `events_actions*` | one tap | Singapore date | `event.category = 'flights_booking_history_details'`, `event.object` `download_ticket` or `resend_ticket`; `event.value` is a bare ref in older builds, `{"booking_ref","booking_status"}` since Sep 2026; `event.id` is the page view's id on web and iOS, not Android |

Clocks: web rows use `server.created_at` (browser clocks drift by minutes to an hour). App rows use the device `created_at`, because the app uploads in batches and `server.created_at` is the upload time; the last few days of app counts keep rising for about a week. Shards here are Singapore days (16:00 to 16:00 UTC), unlike the UTC days of `integrated_bookings_flights`, so a suffix range needs a day of slack on each side.

Sign-in on web is an absence: roxana and olympias send `client.user_hash` from the signed-in user and send it empty otherwise. Owner means `client.user_hash` equals `bookings.user_hash`; a guest booking has no `bookings.user_id_hash`. The app has no sign-in on this screen. Genzo records taps only, never whether a button was shown or what happened after the tap.

## What an EMAIL_LOG row proves

A `provider_exchange_logs` row with `type = 'EMAIL_LOG'` means wego-fares handed one email to wego-crm and records the HTTP status wego-crm answered. It does not carry the email type. Identify the email by timing: within an hour after `cancelled_at` it is the cancellation email; a few seconds after the ticketing request it is the "booking confirmed" email.

wego-crm answers 200 when the job is queued, not when it is delivered, and answers 200 for a malformed address by design. So `status = 200` means accepted by the relay, nothing more. Delivery would need SES event data, which is not in BigQuery.

## Queue numbers seen at the moment a booking changes state

| Queue | GDS | What produced the event |
|---|---|---|
| 50, 500 | Travelport, Sabre | placed on the ticketing queue after payment |
| 51, 501 | Travelport, Sabre | ticketing success poll |
| 52, 502 | Travelport, Sabre | ticketing failed poll (stale fare); sets `qct_status = FAILED` only, booking unchanged |
| 53, 503 | Travelport, Sabre | needs action (PNR data gap) |
| 41 | Travelport | ops-cancellation sweep. Cancels the booking and voids the hold. Emails the customer **only when the booking ends `CANCELLED` with payment `VOIDED`**, since 23 Sep 2026; before that date it emailed none. A voluntary cancel of an already-ticketed booking reaches the same sweep with payment `CAPTURED` and is deliberately not emailed here |
| 201 | Sabre | ops-cancellation sweep. Same `CANCELLED` + `VOIDED` gate as queue 41, since PR #3002 (Jul 2025), but **without** queue 41's guard limiting the email to bookings this pass actually cancelled. Sabre drains its queue when it reads it, so a booking is not normally re-presented; Travelport drains after the pass, which is why only that side needed the guard |
| 203 | Sabre | voluntary exchange |
| none | LCC and direct | the supplier has no GDS queue at all; the success task polls the database |

**`no_queue_event` in `behavior_trace` is not the same thing as the `none` row above.** The table
row means the supplier has no queues. The rendered value means no queue event fell in the window
around the state change, which is `event_at` minus 2 minutes to plus 1 minute. A TRAVELPORT booking
can show `no_queue_event`; it never has "no GDS queue".

A booking that ends `CANCELLED / FAILED_TICKETING / VOIDED` through queue 41 and one through queue 201 are the same customer outcome produced by different code, which is why the queue column is in `behavior_trace`.

## Not in BigQuery

Naming a gap is only half an answer, so each row says where the answer does live.

| Not here | Where it lives |
|---|---|
| Application exceptions and stack traces | Datadog, 13-day retention, and Sentry |
| Whether an email was delivered, opened or bounced | SES event data. An `EMAIL_LOG` row only proves wego-crm accepted it |
| Why a CS agent took an action | The Sprinklr case. The admin note records the action, never the reason, so a question about intent ends here and continues with whoever owns that case |
| Whether a My Trips button was shown, or a download succeeded | Nowhere. Genzo records the tap; wego-fares keeps only sampled spans for the e-ticket endpoints |

Athena and read-only RDS exist but are not reachable from a standard team machine; do not plan on them.
