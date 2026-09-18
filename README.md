# post-booking-cx-skills

Skills for the post-booking CX team. Each one turns a question someone actually asks into a structured answer from the data, so the same question is not re-investigated by hand next time.

One rule for this repo: everything in it must earn its place. A skill goes in when the question has been asked twice; a file goes in when a run without it went wrong.

## Skills

| Skill | Answers |
|---|---|
| [`post-booking-check`](skills/post-booking-check/SKILL.md) | What happened to one booking, what happened to every booking that ended in a state, and whether a release changed post-booking outcomes. BigQuery. |

## Use it

Claude Code, from this repo or by symlinking the skill into your own:

```
ln -s "$PWD/skills/post-booking-check" ~/.claude/skills/post-booking-check
```

Then `/post-booking-check trace WFV517C4KKF26`, or just ask the question; the skill triggers on booking references, booking states and release checks.

The first run tells you what to connect. Currently that is the Google Cloud SDK signed in to `wego-cloud`.

## Repos in scope

wego-fares, flight-integrations, roxana, olympias, orchard, wego-ai. Release-impact metrics exist today for the first two; the front-end and CS repos resolve a release time but their customer-visible effect lives in tables not yet wired in.
