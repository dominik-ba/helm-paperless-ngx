# CLAUDE.md

Read **`AGENTS.md`** in the repository root first. It holds the repository purpose,
layout, commands, release flow, conventions and security notes. This file only adds
Claude Code operating rules and does not repeat that content.

## Operating rules for this repository

- Before reporting a change as done, run the checks in "Validation expectations" in
  `AGENTS.md` and report the actual output.
- Any change to what the chart renders needs a `version:` bump in `Chart.yaml`, because
  released versions are immutable. Say which bump you chose and why.
- This chart is consumed by `gitops/helm/paperless-app` in `dominik-ba/my-raspi-cluster`.
  When a change alters rendered output, call out the effect on that deployment.
- Do not weaken workflow permissions or switch CI to `pull_request_target`; fork PRs
  must stay without secrets and write access.
- No secrets belong in this repository.
