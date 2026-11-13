# <What the customer sees go wrong, or will be able to do, in one line>

Project: PBC · Repo: <owner/repo, comma-separated if several> · Priority: <P1/P2> · Parent: <PBC-xx or none>

> Updated <date>: <only when updating an existing ticket; what changed and why>

<Leave out any section the work does not need. Keep the order.>

## Problem

<One paragraph in plain words. Who the customer is, what they were told or tried, what happened
instead or what they cannot do today. No code names.>

<One sizing line: "<count> bookings ended <state> between <date> and <date>, <count> emailed.
Source: <tool or query>." If nothing measured it, say so and why.>

## Cause

<Why it happens, in domain words: which job or path ends the booking and does not send the email.>

<The precedent: "The <twin job> gained this step in <month year>, wego-fares PR #<n>. Copy that
pattern and its condition.">

## Scope

<Only when Problem does not make it obvious. A small table when the work has levels, channels or
variants.>

## Behaviour

| Given | When | Then |
|---|---|---|
| <the state, in plain words> | <what the customer or the job does> | <what happens, with the exact customer-facing reply in quotes when there is one> |
| <Rules that must not change get a row too, for example existing suppression.> | | |

## Open decisions

| Decision | Proposal | Decided by |
|---|---|---|
| <what the build needs that no source decided> | <your proposal> | <a person only if a source names them; otherwise empty> |

## Out of scope

- <Every finding from the sources this ticket does not act on. One line each.> Separate ticket.
- <...> Separate investigation.
- <...> With <team>.

## Done when

- On staging: <the observable event, within <time> of <trigger>; each Behaviour row holds>.
- Before: <the detailed numbers, one line per row that the change should move>.
- In production, <n> days after release: <the measurement>, from about <before> to about <after>.
  Check with `behavior-trace` or `release-impact`, or the query in the report.

## Notes for the builder

- <Code-level facts: the state values, rule and handoff names, the condition copied from the precedent.>
- <Every place that reads, branches on or shows a changed value, and what each needs.>
- <Tests, as behaviour, one line per case, when Behaviour does not already cover them.>
- <Several repos: a Repo | Change table, one row per repo, then the order they ship in.>

## Sources

- Report: <link>
- Threads: <link>, <link>
- Precedent: wego-fares PR #<n>
- Reference bookings: [WF...](https://backoffice.wego.net/flights/bookings/v2/WF...), <date>, <cost>
- Checked at: <repo>@<commit>, one line per repo
