# <What the customer sees go wrong, in one line>

Project: PBC · Repo: <owner/repo> · Priority: <P1/P2> · Parent: <PBC-xx or none>

> Updated <date>: <only when updating an existing ticket; what changed and why>

## What's broken

<One paragraph. Who the customer is, what they were told, what happened instead. Name the
supplier, the queue, the end states, the email type. No file names.>

<The numbers. Each with its window and where it was measured:
"<count> bookings ended <state> between <date> and <date>, <count> emailed. Source: <report>.">

<Reference cases, as links: [WF...](https://backoffice.wego.net/flights/bookings/v2/WF...), <date>, <cost>.>

## Why

<The cause in domain words: which job or path ends the booking and does not send the email.>

<The precedent: "The <twin job> gained this step in <month year>, wego-fares PR #<n>. Copy that
pattern and its condition.">

## Change

1. <Deliverable one. What changes, named by what the code does. The condition, copied from the precedent.>
2. <Deliverable two, if any. Rules that must not change, for example existing suppression.>
3. <Tests: one line per case, as behaviour, not method names.>

## Out of scope

- <Every finding from the sources this ticket does not act on. One line each.> Separate ticket.
- <...> Separate investigation.
- <...> With <team>.

## Done when

- On staging: <the observable event, within <time> of <trigger>>.
- In production, <n> days after release: <the measurement>, from about <before> to about <after>.
  Check with `behavior-trace` or `release-impact`, or the query in the report.

## Sources

- Report: <link>
- Threads: <link>, <link>
- Precedent: wego-fares PR #<n>
