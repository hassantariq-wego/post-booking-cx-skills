-- Post-booking outcomes for bookings created in the N days before a release versus the N days after.
-- param: at TIMESTAMP
-- param: days INT64
-- param: gds STRING
-- param: from_shard STRING
-- param: to_shard STRING
-- at = release time in UTC. from_shard/to_shard (YYYYMMDD) must cover at-days .. at+days.
-- Pass '' for gds to mean "any".
-- released_money counts booking_status IN ('CANCELLED','FAILED') with payment VOIDED. A FAILED
-- booking was never cancelled, so it has no cancelled_at: that is released_never_cancelled, and
-- it is expected, not missing data. released_and_emailed needs cancelled_at to measure a window,
-- so the email rate's denominator is released_money MINUS released_never_cancelled, never
-- released_money itself. Sabre is usually almost all FAILED, which is why it can read 0 of 60.
WITH b AS (
  SELECT DISTINCT b.id, b.booking_ref, i.integration_type, b.booking_status, b.payment_status,
         b.cancellation_reason, b.created_at, b.cancelled_at, b.completed_at,
         IF(b.created_at < @at, 'before', 'after') AS period
  FROM `wego-cloud.integrated_bookings_flights.bookings*` b
  JOIN `wego-cloud.integrated_bookings_flights.itineraries*` i
    ON i.booking_id = b.id AND i._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard
  WHERE b._TABLE_SUFFIX BETWEEN @from_shard AND @to_shard
    AND b.created_at BETWEEN TIMESTAMP_SUB(@at, INTERVAL @days DAY) AND TIMESTAMP_ADD(@at, INTERVAL @days DAY)
    AND (@gds = '' OR i.integration_type = @gds)
    -- money moved: excludes abandoned checkouts and declines, which never reach post-booking
    AND b.payment_status IN ('AUTHORIZED', 'CAPTURED', 'VOIDED', 'REFUNDED', 'CAPTURE_FAILED',
                             'VOID_FAILED', 'VOID_DECLINED', 'REFUND_FAILED', 'CANCELED')
),
e AS (
  SELECT b.booking_ref,
         COUNTIF(x.requested_at BETWEEN b.cancelled_at AND TIMESTAMP_ADD(b.cancelled_at, INTERVAL 60 MINUTE)) AS cancel_email
  FROM b LEFT JOIN `wego-cloud.integrated_bookings_flights.provider_exchange_logs*` x
    ON x.wego_ref = b.booking_ref AND x.type = 'EMAIL_LOG'
   AND x._TABLE_SUFFIX BETWEEN @from_shard AND FORMAT_DATE('%Y%m%d', DATE_ADD(PARSE_DATE('%Y%m%d', @to_shard), INTERVAL 45 DAY))
  WHERE b.cancelled_at IS NOT NULL
  GROUP BY 1
),
r AS (
SELECT period, integration_type,
       COUNT(*) AS paid_bookings,
       COUNTIF(completed_at IS NOT NULL) AS ticketed,
       ROUND(100 * COUNTIF(completed_at IS NOT NULL) / COUNT(*), 1) AS ticketed_pct,
       COUNTIF(booking_status IN ('CANCELLED', 'FAILED') AND cancellation_reason = 'FAILED_TICKETING') AS failed_ticketing,
       COUNTIF(booking_status = 'REVIEW_IN_PROCESS') AS review_in_process,
       COUNTIF(booking_status = 'TICKETINPROCESS') AS stuck_in_ticketing,
       COUNTIF(booking_status IN ('CANCELLED', 'FAILED') AND payment_status = 'VOIDED') AS released_money,
       COUNTIF(booking_status IN ('CANCELLED', 'FAILED') AND payment_status = 'VOIDED' AND e.cancel_email > 0) AS released_and_emailed,
       COUNTIF(booking_status IN ('CANCELLED', 'FAILED') AND payment_status = 'VOIDED' AND cancelled_at IS NULL) AS released_never_cancelled,
       APPROX_QUANTILES(TIMESTAMP_DIFF(completed_at, created_at, MINUTE), 2)[OFFSET(1)] AS median_minutes_to_ticket
FROM b LEFT JOIN e USING (booking_ref)
GROUP BY ROLLUP (period, integration_type)
HAVING period IS NOT NULL
)
SELECT period, IFNULL(integration_type, 'ALL') AS provider, * EXCEPT (period, integration_type)
FROM r
ORDER BY integration_type IS NULL DESC, paid_bookings DESC, integration_type, period = 'after'
