-- What happened next to every booking that ended in a given state during a window.
-- param: booking_status STRING
-- param: cancellation_reason STRING
-- param: payment_status STRING
-- param: gds STRING
-- param: from_shard STRING
-- param: to_shard STRING
-- param: event_from STRING
-- param: event_to STRING
-- Pass '' for cancellation_reason, payment_status, gds, event_from or event_to to mean "any".
-- from_shard/to_shard (YYYYMMDD) bound the booking creation date.
-- event_from/event_to (e.g. '2026-09-23 06:39:27+00') bound when the booking CHANGED STATE,
-- which is what answers "since the release". Half-open: event_from inclusive, event_to exclusive.
-- Keep the shard window wide enough to still contain those bookings' creation dates.
-- Rows are split by cancellation_reason and payment_status as well as GDS and queue, because
-- one queue routinely carries several outcomes and a combined row hides which is which.
-- example_refs gives up to 5 booking references per row so a surprising row can be opened
-- in booking-trace without dropping to hand-written SQL.
-- emailed_ever_before is UNBOUNDED (any EMAIL_LOG before the state change, usually an earlier
-- e-ticket or confirmation); emailed_1h_after is capped at 60 minutes. The windows differ.
-- Both, and every departs_* column, are measured from event_at =
-- COALESCE(cancelled_at, completed_at, updated_at). queues counts queue events in the window
-- event_at minus 2 minutes to event_at plus 1 minute, so 'no_queue_event' is a statement about
-- that window, NOT about the supplier having no queues.
WITH b0 AS (
  SELECT DISTINCT b.id, b.booking_ref, i.integration_type,
         b.cancellation_reason, b.payment_status,
         COALESCE(b.cancelled_at, b.completed_at, b.updated_at) AS event_at
  FROM `wego-cloud.integrated_bookings_flights.bookings*` b
  JOIN `wego-cloud.integrated_bookings_flights.itineraries*` i
    ON i.booking_id = b.id AND i._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard
  WHERE b._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard
    AND b.booking_status = @booking_status
    AND (@cancellation_reason = '' OR b.cancellation_reason = @cancellation_reason)
    AND (@payment_status = '' OR b.payment_status = @payment_status)
    AND (@gds = '' OR i.integration_type = @gds)
),
b AS (
  SELECT * FROM b0
  WHERE (@event_from = '' OR event_at >= TIMESTAMP(NULLIF(@event_from, '')))
    AND (@event_to   = '' OR event_at <  TIMESTAMP(NULLIF(@event_to,   '')))
),
q AS (
  SELECT b.booking_ref,
         STRING_AGG(DISTINCT CAST(qe.queue_number AS STRING), ' ' ORDER BY CAST(qe.queue_number AS STRING)) AS queues_at_event
  FROM b JOIN `wego-cloud.integrated_bookings_flights.queue_events` qe
    ON qe.booking_id = b.id
   AND qe.created_at BETWEEN TIMESTAMP_SUB(b.event_at, INTERVAL 2 MINUTE) AND TIMESTAMP_ADD(b.event_at, INTERVAL 1 MINUTE)
  GROUP BY 1
),
e AS (
  SELECT b.booking_ref,
         COUNTIF(x.requested_at < b.event_at) AS emails_before,
         COUNTIF(x.requested_at BETWEEN b.event_at AND TIMESTAMP_ADD(b.event_at, INTERVAL 60 MINUTE)) AS emails_within_1h_after
  FROM b LEFT JOIN `wego-cloud.integrated_bookings_flights.provider_exchange_logs*` x
    ON x.wego_ref = b.booking_ref AND x.type = 'EMAIL_LOG'
   AND x._TABLE_SUFFIX BETWEEN @from_shard AND FORMAT_DATE('%Y%m%d', DATE_ADD(PARSE_DATE('%Y%m%d', @to_shard), INTERVAL 45 DAY))
  GROUP BY 1
),
d AS (
  SELECT b.booking_ref, MIN(l.scd_dep_date_time_utc) AS first_departure
  FROM b JOIN `wego-cloud.integrated_bookings_flights.itineraries*` i
    ON i.booking_id = b.id AND i._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard
  JOIN `wego-cloud.integrated_bookings_flights.legs*` l
    ON l.itinerary_id = i.id AND l._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard
  GROUP BY 1
)
SELECT b.integration_type AS gds,
       IFNULL(q.queues_at_event, 'no_queue_event') AS queues,
       IFNULL(b.cancellation_reason, 'none') AS reason,
       IFNULL(b.payment_status, 'none') AS payment,
       COUNT(*) AS bookings,
       COUNTIF(e.emails_before > 0) AS emailed_ever_before,
       COUNTIF(e.emails_within_1h_after > 0) AS emailed_1h_after,
       COUNTIF(TIMESTAMP_DIFF(d.first_departure, b.event_at, HOUR) BETWEEN 0 AND 23) AS departs_under_1d,
       COUNTIF(TIMESTAMP_DIFF(d.first_departure, b.event_at, HOUR) BETWEEN 24 AND 167) AS departs_1_to_7d,
       COUNTIF(TIMESTAMP_DIFF(d.first_departure, b.event_at, HOUR) >= 168) AS departs_over_7d,
       COUNTIF(d.first_departure < b.event_at) AS already_departed,
       STRING_AGG(b.booking_ref, ' ' ORDER BY b.event_at DESC LIMIT 5) AS example_refs
FROM b
LEFT JOIN q USING (booking_ref)
LEFT JOIN e USING (booking_ref)
LEFT JOIN d USING (booking_ref)
GROUP BY 1, 2, 3, 4
-- Rows that reached a GDS queue first: they are the ones anyone is looking for, and the
-- no-queue rows are mostly abandoned checkouts that would otherwise bury them by volume.
ORDER BY queues = 'no_queue_event', bookings DESC
