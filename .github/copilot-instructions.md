# GitHub Copilot instructions

Primary guidance for AI agents is in **`AGENTS.md`** at the repository root; read it for
the layout, commands, release flow, conventions and security notes. This file is a
short standalone summary for Copilot Chat, agent mode and Copilot CLI.

## Repository

Generic Helm chart for Paperless-ngx, published to
`oci://ghcr.io/dominik-ba/charts/paperless`. Bitnami `postgresql` and `redis` are
subcharts; Gotenberg and Tika are optional. Site-specific configuration belongs in a
consumer's values file (or a wrapper chart for extra resources), not here.

## Commands

- `helm dependency build .` (from `Chart.lock`), `helm lint . --strict`
- `helm template paperless . --namespace paperless` plus the scenarios in
  `.github/workflows/ci.yml`

## Rules

- A new `version:` in `Chart.yaml` on `main` is a release (`release.yml`). Released
  versions are immutable, so every change to rendered output needs a version bump.
- Images go in `values.yaml` (`repository` + `tag`), never hardcoded in templates.
- No secrets in the repo. Fork PRs run without secrets and with a read-only token: no
  `pull_request_target`, no write permissions or registry logins in PR jobs, actions
  pinned to commit SHAs.
- 2-space YAML indentation, `.editorconfig`, English for code and docs.
