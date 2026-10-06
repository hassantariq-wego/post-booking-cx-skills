---
name: write-ticket
description: Write or update a Jira ticket for a post-booking CX bug so that a fresh AI session, with no memory of the investigation, fixes the right thing in the right place from the ticket alone. Use after an investigation when someone says "write the ticket", "create a ticket for this", "update the ticket", or hands over a report or Slack thread to turn into a ticket. Produces a Markdown ticket body; filing to Jira is the last step and can be skipped.
---

# Write a ticket that fixes first time

A ticket has one reader: an AI session that did not do the investigation. It must find the code
to change and the pattern to copy from the ticket alone, and it must not have to redo any work the
investigation already did. Everything below serves that reader.

## 1. Gather, then search for an existing ticket

1. Collect the sources: the investigation report, the Slack threads, the CS escalations, the
   prior PR if a twin fix exists. Open each one. Do not write from memory of them.
2. Search the project for an existing ticket, including Done:
   `project = PBC AND text ~ "<two or three key terms>"`.
   If one exists, you are **updating**, not writing. Go to section 5 as well.
3. Confirm the repo. If the source does not name it, ask once.

## 2. Fill the template

Use `template.md` in this folder. Six sections, in this order. Nothing else.

| Section | What goes in it | Rule |
|---|---|---|
| What's broken | The customer-visible failure in one paragraph, then the numbers | Every number carries its window and where it was measured |
| Why | The cause in domain words, and the precedent if one exists | Name the twin fix by PR number and say "copy that pattern and its condition" |
| Change | Numbered deliverables, each one testable | Say what changes and where, by what the code does, never by file or line |
| Out of scope | Every finding from the sources this ticket does not act on | One line each, with "separate ticket", "separate investigation", or "with <team>" |
| Done when | A staging check and a production measurement | Name the tool that measures it (`behavior-trace`, `release-impact`, or the report's query) |
| Sources | The report, every thread, the precedent PR | Links, one per line. Booking refs link to the CS admin tool |

Length: 40 to 80 lines. If it is longer, you are writing a plan, not a ticket.

## 3. Name things that do not move

| Allowed, because they survive refactors | Banned, because they go stale |
|---|---|
| Supplier or GDS name (Travelport, Sabre) | File paths |
| Queue numbers (queue 41, queue 201) | Line numbers, in any form |
| Email types (CANCEL_PNR), booking and payment states (CANCELLED, VOIDED) | Class, method, or variable names |
| PR numbers and commit dates | Package names |
| A job or endpoint named by what it does ("the Travelport ops-cancellation sweep") | Code snippets, unless the snippet is itself the decision (a schema, a state table) |

Say "the Sabre cancellation sweep's final step" not `SabreCancellationAndRefundTask.sendVoidEmail`.
A fresh session finds the first with one grep on `CANCEL_PNR`. The second is wrong the day the
method is renamed.

## 4. Check the ticket against its sources, not against the request

This is the check no other skill has, and it is the one that catches the losses. Do it after
writing, before filing.

1. From each source, list every number, every named thing (queue, state, email type, PR, booking
   ref), every decision, and every link.
2. For each item: it is in the ticket, or it is under Out of scope with a pointer, or you can say
   in one line why the reader does not need it.
3. Quote facts exactly. If the report says "the ticket emails for Umrah bookings are suppressed",
   do not write "Umrah bookings are suppressed". Nine of eleven skills softened that one fact.
4. Do not add requirements no source states. Retries, idempotency, observability, or "cover every
   path" go in only if a source asked for them.
5. Do not tell the reader to enumerate, explore, or investigate what a source already enumerated.
   Put the enumeration in the ticket.

Then run the leak scan:

```bash
grep -n -E '\.java\b|src/main|src/test|:[0-9]{2,4}\b|\b[A-Z][a-zA-Z]+(Task|Service|Impl|Helper|Resource|Dao|Client|Command)\b' ticket.md
```

Every hit is a line to rewrite in the words of section 3. Zero hits before filing.

## 5. Updating an existing ticket

Edit in place. Never rewrite from scratch.

1. Add one line at the top: `> Updated <date>: <what changed and why, one sentence>.`
2. Keep the title unless the scope genuinely changed. If it changed, say so in the update line.
3. Keep every fact and every Out of scope line from the previous version unless a source says it
   is wrong. Dropping a fact is a change; name it.
4. A scope decision from the previous version (for example "the catch-all is a separate ticket")
   stays unless the new instruction reverses it. If it reverses it, write the reversal and the
   old reason next to each other.
5. Do not split one ticket into a parent and sub-tasks unless the work lands in two repos.

## 6. Keep it cheaper than the fix

- Ask no question the sources already answer. Read them first.
- Ask at most one question, and only if the answer changes what gets built.
- No epic: PBC has none. Ask for a parent ticket or none.
- No sub-agent review for a ticket that mirrors a named PR. The precedent is the review.

## 7. File it

PBC issue type is `Task` for everything. Create with a one-line stub, then set the body with the
Atlassian MCP `editJiraIssue` using `contentFormat: "markdown"`, then read it back with
`responseContentFormat: "markdown"` and confirm the newlines survived. Booking references are
links to `https://backoffice.wego.net/flights/bookings/v2/<ref>`, never bare text.

If you have no write access (Anya in draft mode, or a bake-off), stop after the checks and hand
over the Markdown body.

## Before you say done

- [ ] Existing ticket searched, including Done.
- [ ] Six sections, 40 to 80 lines.
- [ ] Every number has a window and a source. Every quote matches the source.
- [ ] Precedent named by PR number, if one exists.
- [ ] Leak scan returns nothing.
- [ ] Every unacted source finding is under Out of scope with a pointer.
- [ ] Done when names the tool that measures it.
- [ ] If updating: one dated line at the top, title and prior decisions kept or the change named.
