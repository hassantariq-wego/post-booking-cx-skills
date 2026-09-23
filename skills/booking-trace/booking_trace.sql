-- One booking, every recorded event, in time order. Consecutive identical events (a queue
-- polled every ten minutes, say) collapse into one row with a count and a time span.
-- param: ref STRING
-- param: from_shard STRING
-- param: to_shard STRING
-- from_shard/to_shard are YYYYMMDD and bound the sharded tables. Start with the booking's
-- creation date and 45 days after it; widen if the trace looks cut off.
WITH b AS (
  SELECT id, booking_ref, booking_status, payment_status, cancellation_reason, booking_type,
         booking_mode, payment_order_id, created_at, cancelled_at, completed_at
  FROM `wego-cloud.integrated_bookings_flights.bookings*`
  WHERE _TABLE_SUFFIX BETWEEN @from_shard AND @to_shard AND booking_ref = @ref
),
i AS (
  SELECT id AS itinerary_id, booking_id, integration_type, gds_ref, itinerary_status, ticket_status, qct_status
  FROM `wego-cloud.integrated_bookings_flights.itineraries*`
  WHERE _TABLE_SUFFIX BETWEEN @from_shard AND @to_shard AND booking_id IN (SELECT id FROM b)
),
events AS (
  SELECT created_at AS ts, 'booking' AS source, 'created' AS event,
         CONCAT(booking_type, ' ', booking_mode, ' · now ', booking_status, ' / ', payment_status,
                IFNULL(CONCAT(' / ', cancellation_reason), '')) AS detail
  FROM b
  UNION ALL
  SELECT p.created_at, 'payment', CONCAT('created ', p.status), CONCAT(p.payment_method_code, ' · now ', p.status, ' at ', CAST(p.updated_at AS STRING))
  FROM `wego-cloud.integrated_bookings_flights.payments*` p
  WHERE p._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard AND p.order_id IN (SELECT payment_order_id FROM b)
  UNION ALL
  SELECT x.requested_at, 'exchange', x.type, CONCAT('http ', CAST(x.status AS STRING), IFNULL(CONCAT(' · ', SUBSTR(x.error, 1, 80)), ''))
  FROM `wego-cloud.integrated_bookings_flights.provider_exchange_logs*` x
  WHERE x._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard AND x.wego_ref = @ref
  UNION ALL
  SELECT q.created_at, CONCAT('queue ', q.queue_number), q.status, CONCAT(IFNULL(q.ipcc, ''), ' ', q.gds_ref)
  FROM `wego-cloud.integrated_bookings_flights.queue_events` q
  WHERE q.booking_id IN (SELECT id FROM b)
  UNION ALL
  SELECT cancelled_at, 'booking', 'cancelled', CONCAT(booking_status, ' / ', payment_status, ' / ', cancellation_reason) FROM b WHERE cancelled_at IS NOT NULL
  UNION ALL
  SELECT completed_at, 'booking', 'ticketed', '' FROM b WHERE completed_at IS NOT NULL
  UNION ALL
  SELECT n.created_at, 'admin note', n.created_by, SUBSTR(REPLACE(n.note, '\n', ' '), 1, 160)
  FROM `wego-cloud.integrated_bookings_flights.booking_admin_notes` n
  WHERE n.booking_id IN (SELECT id FROM b)
  UNION ALL
  SELECT l.scd_dep_date_time_utc, 'flight', 'departure', CONCAT(l.departure_airport_code, '-', l.arrival_airport_code, ' · leg ', l.status)
  FROM `wego-cloud.integrated_bookings_flights.legs*` l
  WHERE l._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard AND l.itinerary_id IN (SELECT itinerary_id FROM i)
  UNION ALL
  SELECT NULL, 'itinerary', CONCAT(integration_type, ' ', gds_ref), CONCAT(itinerary_status, ' / ticket ', ticket_status, ' / qct ', IFNULL(qct_status, '-'))
  FROM i
),
ordered AS (
  SELECT *, IF(source = LAG(source) OVER w AND event = LAG(event) OVER w, 0, 1) AS starts_run
  FROM events
  WINDOW w AS (ORDER BY ts NULLS FIRST, source, event)
),
runs AS (
  SELECT *, SUM(starts_run) OVER (ORDER BY ts NULLS FIRST, source, event) AS run_id FROM ordered
)
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', MIN(ts)) AS utc,
       ANY_VALUE(source) AS source,
       ANY_VALUE(event) AS event,
       IF(COUNT(*) = 1, ANY_VALUE(detail),
          CONCAT(CAST(COUNT(*) AS STRING), ' times until ', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', MAX(ts)), ' · ', ANY_VALUE(detail))) AS detail
FROM runs
GROUP BY run_id
ORDER BY MIN(ts) NULLS FIRST
