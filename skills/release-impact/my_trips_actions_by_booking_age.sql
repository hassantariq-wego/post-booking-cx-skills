-- My Trips booking-details page: owner sessions and Download taps split by how long ago the booking was made, before versus after a release. A booking made in the last day means the owner signed in recently.
-- param: at TIMESTAMP
-- param: before_days INT64
-- param: until TIMESTAMP
-- param: surfaces STRING
-- at = the time the new version first served, UTC. before = [at - before_days, at). after = [at, until).
-- until must be at least two hours before now: the e-tickets table lands about an hour late, and a tap
-- whose e-ticket row has not arrived reads "e-ticket not issued yet".
-- surfaces = web (roxana desktop web + olympias mobile web), app (the orchard miniapp inside the iOS and
-- Android apps) or all. The app does not ship with a web release, so it is the control for one.
-- Visitor classes come from Genzo client.user_hash against bookings.user_hash: on web an empty hash is a
-- signed-out visitor; a booking with no user_id_hash was made as a guest.
-- Web timestamps are server.created_at (browser clocks drift); app timestamps are the device created_at
-- (the app uploads in batches, so server time is the upload time). Genzo shards are Singapore days, so the
-- suffix range carries a day of slack on each side.
WITH w AS (
  SELECT period, ts0, ts1, TIMESTAMP_DIFF(ts1, ts0, MINUTE) / 1440.0 AS days
  FROM UNNEST([STRUCT('before' AS period, TIMESTAMP_SUB(@at, INTERVAL @before_days DAY) AS ts0, @at AS ts1),
               STRUCT('after' AS period, @at AS ts0, @until AS ts1)])),
sf AS (
  SELECT app, surface FROM UNNEST([
    STRUCT('WEB_APP' AS app, 'Desktop web' AS surface), ('MOBILE_WEB_APP', 'Mobile web'),
    ('IOS_APP', 'App'), ('ANDROID_APP', 'App'), ('IOS_TABLET_APP', 'App'), ('ANDROID_TABLET_APP', 'App')])
  WHERE CASE @surfaces WHEN 'all' THEN TRUE WHEN 'web' THEN surface <> 'App' WHEN 'app' THEN surface = 'App'
        ELSE ERROR('surfaces must be web, app or all') END),
pv AS (
  SELECT w.period, sf.surface, p.id AS pv_id, p.client.session_id AS sid, p.client.user_hash AS uh,
         IF(sf.surface = 'App', p.created_at, p.server.created_at) AS ts,
         UPPER(REGEXP_EXTRACT(p.page.url, r'(?i)(WF[A-Z0-9]{11})')) AS ref
  FROM `wego-cloud.services_genzo.pages_views*` p
  JOIN sf ON sf.app = p.device.app
  JOIN w ON IF(sf.surface = 'App', p.created_at, p.server.created_at) >= w.ts0
        AND IF(sf.surface = 'App', p.created_at, p.server.created_at) < w.ts1
  WHERE p._TABLE_SUFFIX BETWEEN FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_SUB(@at, INTERVAL @before_days + 1 DAY))
                            AND FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_ADD(@until, INTERVAL 1 DAY))
    AND p.page.sub_type = 'flight_booking_history_details'),
ev AS (
  SELECT FARM_FINGERPRINT(CONCAT(sf.surface, IFNULL(e.client.user_hash, ''), IFNULL(e.event.id, ''),
                                 CAST(e.created_at AS STRING), e.event.object, IFNULL(e.event.value, ''))) AS rk,
         w.period, sf.surface, e.event.id AS pv_id, e.client.user_hash AS uh,
         IF(sf.surface = 'App', e.created_at, e.server.created_at) AS ts, e.event.object AS obj,
         -- event.value is a bare booking ref in older builds and {"booking_ref","booking_status"} since Sep 2026
         UPPER(IF(STARTS_WITH(e.event.value, '{'), JSON_VALUE(e.event.value, '$.booking_ref'), e.event.value)) AS ref
  FROM `wego-cloud.services_genzo.events_actions*` e
  JOIN sf ON sf.app = e.device.app
  JOIN w ON IF(sf.surface = 'App', e.created_at, e.server.created_at) >= w.ts0
        AND IF(sf.surface = 'App', e.created_at, e.server.created_at) < w.ts1
  WHERE e._TABLE_SUFFIX BETWEEN FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_SUB(@at, INTERVAL @before_days + 1 DAY))
                            AND FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_ADD(@until, INTERVAL 1 DAY))
    AND e.event.category = 'flights_booking_history_details'
    AND e.event.object IN ('download_ticket', 'resend_ticket')),
refs AS (SELECT DISTINCT ref FROM pv WHERE ref IS NOT NULL UNION DISTINCT SELECT DISTINCT ref FROM ev WHERE ref IS NOT NULL),
bk AS (
  SELECT b.booking_ref AS ref, b.id AS booking_id, b.user_hash AS b_uh, b.user_id_hash, b.booking_status,
         b.cancelled_at, b.created_at AS booked_at
  FROM `wego-cloud.integrated_bookings_flights.bookings*` b JOIN refs r ON r.ref = b.booking_ref
  WHERE b._TABLE_SUFFIX BETWEEN '20230101' AND FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_ADD(@until, INTERVAL 1 DAY))),
tk AS (
  SELECT i.booking_id, MIN(et.created_at) AS first_eticket_at, MAX(s.scd_arr_date_time_utc) AS last_arr_utc
  FROM `wego-cloud.integrated_bookings_flights.itineraries*` i
  JOIN (SELECT DISTINCT booking_id FROM bk) ids ON ids.booking_id = i.booking_id
  JOIN `wego-cloud.integrated_bookings_flights.legs*` l ON l.itinerary_id = i.id
  JOIN `wego-cloud.integrated_bookings_flights.segments*` s ON s.leg_id = l.id
  LEFT JOIN `wego-cloud.integrated_bookings_flights.etickets` et ON et.segment_id = s.id
  WHERE i._TABLE_SUFFIX BETWEEN '20230101' AND FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_ADD(@until, INTERVAL 1 DAY))
    AND l._TABLE_SUFFIX BETWEEN '20230101' AND FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_ADD(@until, INTERVAL 1 DAY))
    AND s._TABLE_SUFFIX BETWEEN '20230101' AND FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_ADD(@until, INTERVAL 1 DAY))
  GROUP BY 1),
bkx AS (SELECT bk.*, tk.first_eticket_at, tk.last_arr_utc FROM bk LEFT JOIN tk USING (booking_id)),
-- a resend that reached wego-fares shows as an EMAIL_LOG call for the booking within 60 s of the tap
em AS (
  SELECT wego_ref, requested_at FROM `wego-cloud.integrated_bookings_flights.provider_exchange_logs*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_SUB(@at, INTERVAL @before_days + 1 DAY))
                          AND FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_ADD(@until, INTERVAL 1 DAY))
    AND type = 'EMAIL_LOG'),
emk AS (
  SELECT e.rk, COUNT(em.wego_ref) > 0 AS emailed
  FROM ev e LEFT JOIN em ON em.wego_ref = e.ref
   AND em.requested_at BETWEEN TIMESTAMP_SUB(e.ts, INTERVAL 5 SECOND) AND TIMESTAMP_ADD(e.ts, INTERVAL 60 SECOND)
  WHERE e.obj = 'resend_ticket' GROUP BY 1),
pvc AS (
  SELECT p.*, b.booked_at,
    CASE WHEN p.surface <> 'App' AND (p.uh IS NULL OR p.uh = '') THEN '1 Signed out'
         WHEN p.ref IS NULL THEN '9 No booking ref in URL'
         WHEN b.ref IS NULL THEN '9 Booking not found'
         WHEN b.user_id_hash IS NOT NULL AND p.uh = b.b_uh THEN '2 Signed in - own booking'
         WHEN b.user_id_hash IS NULL THEN '4 Signed in - guest booking'
         ELSE '3 Signed in - another account' END AS who,
    CASE WHEN p.ref IS NULL OR b.ref IS NULL THEN 'unknown'
         WHEN b.cancelled_at IS NOT NULL AND b.cancelled_at < p.ts THEN '4 cancelled before the visit'
         WHEN b.cancelled_at IS NULL AND b.booking_status IN ('FAILED', 'VOIDED', 'ONHOLD', 'BOOKING_REQUESTED', 'REVIEW_IN_PROCESS', 'EXPIRED') THEN '4 cancelled before the visit'
         WHEN b.first_eticket_at IS NULL OR b.first_eticket_at > p.ts THEN '1 e-ticket not issued yet'
         WHEN b.last_arr_utc < p.ts THEN '3 flown'
         ELSE '2 issued, trip upcoming' END AS state
  FROM pv p LEFT JOIN bkx b USING (ref)),
evc AS (
  SELECT e.*,
    CASE WHEN e.surface <> 'App' AND (e.uh IS NULL OR e.uh = '') THEN '1 Signed out'
         WHEN b.ref IS NULL THEN '9 Booking not found'
         WHEN b.user_id_hash IS NOT NULL AND e.uh = b.b_uh THEN '2 Signed in - own booking'
         WHEN b.user_id_hash IS NULL THEN '4 Signed in - guest booking'
         ELSE '3 Signed in - another account' END AS who,
    CASE WHEN b.ref IS NULL THEN 'unknown'
         WHEN b.cancelled_at IS NOT NULL AND b.cancelled_at < e.ts THEN '4 cancelled before the visit'
         WHEN b.cancelled_at IS NULL AND b.booking_status IN ('FAILED', 'VOIDED', 'ONHOLD', 'BOOKING_REQUESTED', 'REVIEW_IN_PROCESS', 'EXPIRED') THEN '4 cancelled before the visit'
         WHEN b.first_eticket_at IS NULL OR b.first_eticket_at > e.ts THEN '1 e-ticket not issued yet'
         WHEN b.last_arr_utc < e.ts THEN '3 flown'
         ELSE '2 issued, trip upcoming' END AS state,
    -- a tap's session is its page view's session; Android taps carry no page-view id, so fall back to visitor+booking+day
    COALESCE(s.sid, CONCAT(IFNULL(e.uh, ''), '|', IFNULL(e.ref, ''), '|', CAST(DATE(e.ts) AS STRING))) AS skey,
    COALESCE(k.emailed, FALSE) AS emailed
  FROM ev e LEFT JOIN bkx b USING (ref)
  LEFT JOIN (SELECT pv_id, ANY_VALUE(sid) AS sid FROM pv GROUP BY 1) s ON s.pv_id = e.pv_id
  LEFT JOIN emk k ON k.rk = e.rk)
, S AS (
  SELECT surface, period, sid,
         ANY_VALUE(CASE WHEN TIMESTAMP_DIFF(ts, booked_at, HOUR) < 24 THEN 'a <1 day'
                        WHEN TIMESTAMP_DIFF(ts, booked_at, DAY) < 4 THEN 'b 1-3 days'
                        WHEN TIMESTAMP_DIFF(ts, booked_at, DAY) < 15 THEN 'c 4-14 days'
                        ELSE 'd 15+ days' END) AS booking_age
  FROM pvc WHERE who = '2 Signed in - own booking' AND state = '2 issued, trip upcoming' GROUP BY 1, 2, 3),
D AS (
  SELECT surface, period, skey, COUNTIF(obj = 'download_ticket') > 0 AS downloaded, COUNTIF(obj = 'resend_ticket') AS rs_taps
  FROM evc WHERE who = '2 Signed in - own booking' AND state = '2 issued, trip upcoming' GROUP BY 1, 2, 3)
SELECT s.surface, s.booking_age, s.period, COUNT(*) AS sessions, COUNTIF(d.downloaded) AS dl_sessions,
       ROUND(SAFE_DIVIDE(COUNTIF(d.downloaded), COUNT(*)), 2) AS dl_rate, IFNULL(SUM(d.rs_taps), 0) AS rs_taps
FROM S s LEFT JOIN D d ON d.surface = s.surface AND d.period = s.period AND d.skey = s.sid
GROUP BY 1, 2, 3 ORDER BY 1, 2, s.period = 'after'
