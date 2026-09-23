# post-booking-cx-skills

Skills for the post-booking CX team. Each one turns a question someone actually asks into a structured answer from the data, so the same question is not re-investigated by hand next time.

One rule for this repo: everything in it must earn its place. A skill goes in when the question has been asked twice; a file goes in when a run without it went wrong.

## Skills

| Skill | Answers |
|---|---|
| [`booking-trace`](skills/booking-trace/SKILL.md) | What happened to one booking, every event in order |
| [`behavior-trace`](skills/behavior-trace/SKILL.md) | What happened next to every booking that ended in a state over a period |
| [`release-impact`](skills/release-impact/SKILL.md) | Whether a release changed post-booking outcomes, before versus after |
| [`write-ticket`](skills/write-ticket/SKILL.md) | A Jira ticket a fresh AI session can fix from, after an investigation |

All three read BigQuery `wego-cloud.integrated_bookings_flights` through the shared runner in `skills/_shared`, which also holds the preflight check and the data reference.

## Use it

Claude Code: symlink the skills into your own skills folder, then ask the question or invoke by name.

```
for s in booking-trace behavior-trace release-impact write-ticket; do ln -sfn "$PWD/skills/$s" ~/.claude/skills/$s; done
```

The first run tells you what to connect. Currently that is the Google Cloud SDK signed in to `wego-cloud`.

## Repos in scope

wego-fares, flight-integrations, roxana, olympias, orchard, wego-ai. Release-impact metrics exist today for the first two; the front-end and CS repos resolve a release time but their customer-visible effect lives in tables not yet wired in.
