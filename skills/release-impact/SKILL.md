---
name: release-impact
description: Compare what customers experienced after a booking before versus after a release, from BigQuery. For wego-fares and flight-integrations releases it reports booking outcomes per GDS plus an all-GDS row (ticketing rates, failures, cancellations, customer emails, time to ticket). For roxana, olympias and orchard releases it reports My Trips booking-details sessions and e-ticket Download and Resend taps per visitor class (owner, another account, guest booking, signed out) and booking state. Use it whenever someone asks whether a release, deploy or merged PR changed anything, or asks to check a ticket's Done-when in production. Trigger on "did the deploy change anything" and "check the impact of the release" even when BigQuery is not mentioned.
---

Answer shape: one or two lines that answer the question, the table, one line naming the dataset, one line naming what the data cannot show. Stop there.

## Before running

Run `../_shared/scripts/preflight.sh`. It checks `bq`, the gcloud login and read access to `wego-cloud.integrated_bookings_flights`, and prints the exact command for anything missing. Show that command to the user and stop until they have run it.

## Which metric set

| Release in | What the tables can see | Query |
|---|---|---|
| wego-fares, flight-integrations | Booking outcomes | `release_impact.sql` |
| roxana (desktop web), olympias (mobile web), orchard (the miniapp inside the iOS and Android apps) | My Trips ticket actions | `my_trips_actions.sql`, plus two diagnostics |
| wego-ai | Nothing yet | Say "metrics for this repo are not defined yet" rather than running a query and implying it measured something |

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

For the web apps the deploy job is a GitHub workflow, and the time to use is its completion:

```
gh run list --repo wego/roxana   --workflow "Deploy main branch to Production"   --json headSha,conclusion,updatedAt
gh run list --repo wego/olympias --workflow "Deploy master branch to Production" --json headSha,conclusion,updatedAt
```

roxana and olympias deploy separately; for a change that shipped in both, take the later one.
roxana ships a service worker, so a returning visitor keeps the old bundle until a later visit
picks up the new one. Expect a web change to ramp over several days and call fewer than seven
after-days an early look, not a verdict.

## Booking outcomes (wego-fares, flight-integrations)

### Run

```
../_shared/scripts/query.sh release_impact.sql "at=2026-09-08 06:17:16" days=7 gds= from_shard=20260901 to_shard=20260915
```

`from_shard` and `to_shard` must cover the whole before-and-after span. Pass an empty `gds` to mean any. The query counts only bookings where money moved, so abandoned checkouts and card declines do not dilute the rates.

### Read the result

Show the ALL row and the GDS rows with enough volume to matter. Flag a delta only when both periods have the volume to support it; a change from 3 to 6 bookings is noise, say so.

`released_and_emailed` counts bookings with a customer email within an hour of `cancelled_at`.

**The email denominator is `released_money` minus `released_never_cancelled`, never `released_money`
itself.** `released_money` counts bookings that ended `CANCELLED` **or** `FAILED` with the hold
released. A FAILED booking was never cancelled, so it has no `cancelled_at`, and the email window is
measured from that column. Those bookings are `released_never_cancelled`: an expected property, not
missing data. Sabre is usually almost entirely FAILED, so it reads `released_money` 60,
`released_and_emailed` 0, `released_never_cancelled` 60. That is 0 of 0 measurable, not a total
email failure, and reporting it as one is the mistake this column exists to prevent.

Show the ALL row and the provider rows with enough volume to matter, not every provider.

## My Trips ticket actions (roxana, olympias, orchard)

### Run

```
../_shared/scripts/query.sh my_trips_actions.sql "at=2026-10-08 07:08:00" before_days=14 "until=2026-10-12 04:00:00" surfaces=web
```

- Times are UTC, whatever the machine's zone. A value with its own offset, such as `2026-10-08T15:08:00+08:00` straight from `git log` or a workflow run, is read correctly too. Never type a local wall-clock time without its offset.
- `at`: when the new version first served. `before_days`: 14 covers two weekly cycles.
- `until`: end of the after window, **at least two hours before now** (`date -u -v-2H '+%Y-%m-%d %H:%M:00'` on macOS, `date -u -d '2 hours ago' '+%Y-%m-%d %H:%M:00'` on Linux). The e-tickets table lands about an hour late, and a tap whose e-ticket row has not arrived is counted under "e-ticket not issued yet" instead of the state that shows the buttons.
- `surfaces`: `web` for a roxana or olympias release, `app` for orchard, `all` for a backend change both read.
- For a web release run it twice, `surfaces=web` for the effect and `surfaces=app` as the control. The app does not ship with the web, so an app row that moves the same way is the season, not the release.
- Shards are derived from the parameters. A run covers about 70 GB for 18 days of web traffic and takes one to two minutes.

### Read the result

Rows are surface × visitor class × booking state × period. The buttons show only when the booking has an e-ticket and the trip is upcoming, so the rows in state `2 issued, trip upcoming` carry the answer; the other states are context.

| Column | Meaning | Source |
|---|---|---|
| `sessions`, `page_views` | Genzo sessions and views of the booking-details page | `services_genzo.pages_views*` |
| `who` | Signed out; own booking; another account; guest booking | Genzo `client.user_hash` against `bookings.user_hash` and `user_id_hash` |
| `state` | e-ticket not issued, issued with trip upcoming, flown, cancelled, as of the view | `bookings*`, `etickets`, `segments*` |
| `dl_sessions`, `dl_taps` | sessions with at least one Download tap, and the taps | `services_genzo.events_actions*` |
| `rs_sessions`, `rs_taps`, `rs_emailed` | the same for Resend; `rs_emailed` is the taps that reached wego-fares, seen as an `EMAIL_LOG` call for the booking within 60 s | `provider_exchange_logs*` |
| `sessions_per_day`, `dl_sessions_per_day`, `dl_rate` | counts over the window length; `dl_rate` is `dl_sessions / sessions` | computed |

Compare rates across periods, not counts: the windows differ in length and sessions move with marketing and the weekday. A button hidden from a class shows as its `dl_sessions` and `rs_taps` going to zero. A changed owner `dl_rate` is the release's effect on owners, wanted or not. `rs_emailed` well below `rs_taps` means those visitors could tap but the backend refused them.

Flag a delta only when both periods have tens of sessions in that row. Single digits are noise, say so.

### When a row moved, run the diagnostics

Same parameters, same cost each.

- `my_trips_actions_by_day.sql`: one row per surface, day and signed-in class, for the state that shows the buttons. A step on the release day is the release. A slope over the days after it is the rollout, or a trend that began before. `dl_taps` far above `dl_sessions` means a few visitors tapping repeatedly, not many visitors.
- `my_trips_actions_by_booking_age.sql`: owner sessions and `dl_rate` by how long ago the booking was made. A drop that spares bookings under a day old (owners who signed in to book) and grows with age points at the page's sign-in state when it loads, not at the booking. A drop across every age points at the button gate itself.

### What the data cannot show

- Whether the button was on screen. Genzo records taps, not impressions, so a fall in `dl_rate` is a fall in taps.
- Whether a download succeeded. The tap is the last trace; wego-fares keeps only sampled spans for the e-ticket endpoints.
- Which bundle a visitor ran. The events carry no build version.
- Sign-in on web is only the absence of a `client.user_hash`. The app has no sign-in on this screen, so its classes are booking ownership only.
- App counts for the last few days keep rising for about a week, because devices upload events in batches.
- Resend taps exist only since the tracking releases of 22 Sep 2026 (web) and 29 Sep 2026 (app). A before window that starts earlier shows `rs_taps` 0 because the event did not exist, not because nobody tapped.

## Rendering

Render a result as a Markdown pipe table when you show it to a person. Pad the cells so the table is aligned as plain text and renders as a real table in Slack, and escape any pipe inside a cell. The query returns CSV because that is what survives a cell containing a comma, a pipe or a newline; do not paste the CSV at someone.
