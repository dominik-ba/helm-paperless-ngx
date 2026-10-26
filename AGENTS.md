# AGENTS.md

Tool-neutral guidance for AI coding agents (GitHub Copilot, Claude Code) working in
this repository. `CLAUDE.md` and `.github/copilot-instructions.md` reference this file;
keep repository facts here and avoid duplicating them elsewhere.

## What this repository is

A generic, reusable Helm chart for [Paperless-ngx](https://docs.paperless-ngx.com/),
published as an OCI artifact to `oci://ghcr.io/dominik-ba/charts/paperless`. The repo is
public; anyone can open pull requests from forks.

The chart has no site-specific configuration (no secret manager, hostnames, node
placement or storage classes). The main consumer is the `paperless-app` wrapper chart
in [dominik-ba/my-raspi-cluster](https://github.com/dominik-ba/my-raspi-cluster)
(`gitops/helm/paperless-app`), which adds 1Password, ingress host and SMB storage and is
deployed by ArgoCD. Site-specific values belong in that wrapper, not here.

## Layout

- `Chart.yaml`: chart metadata, `version` (drives releases), `appVersion` (Paperless-ngx
  image, tracked by Renovate through the `# renovate:` comment) and the Bitnami
  `postgresql` / `redis` subchart dependencies (`oci://registry-1.docker.io/bitnamicharts`).
- `Chart.lock`: pinned dependency versions. Committed; `charts/` and `*.tgz` are not.
- `values.yaml`: all configurable defaults (Paperless, Gotenberg, Tika, persistence,
  ingress, secrets, subchart values).
- `templates/`: Deployment, Service, Ingress, PVCs, Secrets, Gotenberg and Tika.
- `examples/smb-static-pvcs.yaml`: static PV/PVC example for SMB storage.
- `.github/workflows/ci.yml`: PR and main CI (lint, template scenarios, kubeconform,
  plaintext-secret check).
- `.github/workflows/release.yml`: publishes an unreleased `Chart.yaml` version from `main`.
- `renovate.json`: dependency updates, chart version bump, action digest pinning.

## Commands

| Purpose | Command |
| --- | --- |
| Fetch dependencies from `Chart.lock` | `helm dependency build .` |
| Re-resolve dependencies (after editing `Chart.yaml` deps) | `helm dependency update .` |
| Lint | `helm lint . --strict` |
| Render defaults | `helm template paperless . --namespace paperless` |
| Render all optional features | see the last `helm template` step in `.github/workflows/ci.yml` |
| Validate manifests | `kubeconform -strict -summary -ignore-missing-schemas <rendered.yaml>` |

CI uses Helm v4 (`azure/setup-helm`, version in the workflows).

## Validation expectations

Before proposing a change as complete, run and report:

1. `helm dependency build .` and `helm lint . --strict`.
2. The `helm template` scenarios from `ci.yml` (defaults, `secrets.create=true`, all
   optional features) and kubeconform on each output if available.
3. For changes to templates or defaults: a diff of the rendered output before and after
   the change, and a note whether it changes what the `paperless-app` wrapper deploys.

## Releases

- A release is a new `version:` in `Chart.yaml` merged to `main`. `release.yml` then
  pushes `ghcr.io/dominik-ba/charts/paperless:<version>`, tags `v<version>` and creates a
  GitHub Release.
- Released versions are immutable. The workflow never re-pushes a version that already
  has a tag or an OCI artifact. Any change to what the chart renders needs a version bump.
- Renovate bumps the patch version with every subchart or image update. For a manual
  change: patch for fixes, minor for new values or subchart major updates, major for
  breaking value changes.
- Keep the version references in `README.md` (install, ArgoCD and subchart examples,
  dependency table) in sync with `Chart.yaml`.

## Conventions to preserve

- Everything site-specific stays configurable through `values.yaml`; defaults must work
  in a plain cluster.
- Images are set in `values.yaml` (`repository` + `tag`) so Renovate's helm-values manager
  can track them; do not hardcode images in templates.
- PostgreSQL on SMB needs a storage class with strict permissions (see README
  troubleshooting); keep that guidance intact.
- 2-space indentation for YAML, JSON and templates; honor `.editorconfig`.
- English for code, comments and docs.

## Security notes

- No secrets in the repository. Chart-created secrets (`secrets.create=true`) are for
  testing only; the CI plaintext-secret check must keep passing.
- Fork PRs run CI with a read-only `GITHUB_TOKEN` and no secrets. Do not use
  `pull_request_target`, do not add `workflow_run` jobs that consume PR artifacts, and do
  not give PR jobs write permissions or registry logins. Write permissions belong only to
  the release job on `main`.
- Third-party actions are pinned to commit SHAs (Renovate keeps them current). Keep new
  actions pinned the same way.

## Scope limit for agents

Only change what the task asks. Do not change released versions, the release flow or
workflow permissions as a side effect. When an industry best practice would materially
improve the chart, explain the alternative and its trade-offs before applying it.
