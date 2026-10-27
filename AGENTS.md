# AGENTS.md

Tool-neutral guidance for AI coding agents (GitHub Copilot, Claude Code) working in
this repository. `CLAUDE.md` and `.github/copilot-instructions.md` reference this file;
keep repository facts here and avoid duplicating them elsewhere.

## What this repository is

A generic, reusable Helm chart for [Paperless-ngx](https://docs.paperless-ngx.com/),
published as an OCI artifact to `oci://ghcr.io/dominik-ba/charts/paperless`. The repo is
public; anyone can open pull requests from forks.

The chart has no site-specific configuration (no secret manager, hostnames, node
placement or storage classes). Consumers configure it with their own values file and
only need a wrapper chart when they add resources this chart does not render (see
"Site-specific setup" in `README.md`). Site-specific values belong there, not here.

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

## Pitfalls

- **Verify published artifacts without local registry logins.** Helm and Docker fall back to
  a Docker credential store (`credsStore` in `~/.docker/config.json`, e.g. Docker Desktop).
  A stale GHCR login there makes public packages fail with `403 denied`, and
  `--registry-config /dev/null` does not stop Helm from using it. Use an empty
  `DOCKER_CONFIG` directory plus an empty `--registry-config` file, or the anonymous token
  flow: `curl "https://ghcr.io/token?scope=repository:<owner>/<name>:pull&service=ghcr.io"`,
  then `GET https://ghcr.io/v2/<owner>/<name>/tags/list` with the bearer token.
- GHCR package visibility is a separate setting from repository visibility.
- `gh pr edit` can fail with "Projects (classic) is being deprecated". Use
  `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f title=... -F body=@file.md`.
- This repository is public: never reference private consumer repositories (names, paths,
  hostnames, cluster details) in docs, AI files, comments, commit messages or PR texts.
- **Renovate's Docker versioning only compares tags with the same number of parts.** Tika
  publishes four-part 3.x tags (`3.3.3.0`) and three-part 4.x tags (`4.1.0`), so a `3.1.0`
  pin never sees newer 3.x releases. If an image gets no update PRs, check the Dependency
  Dashboard issue and consider a `versioning` regex.
- **Changing a default from a floating tag (`latest`) to a pinned tag** can downgrade
  existing installations: `latest` may already be newer than the pin. Check the newest
  tag of that line and say so in the PR.
- The Bitnami `postgresql`/`redis` subcharts run `latest` images. With `IfNotPresent` the
  version depends on the node's cache; another node pulls today's `latest`. A PostgreSQL
  major change needs a data migration, so mention the current `latest` major in PRs that
  touch these images.

## Scope limit for agents

Only change what the task asks. Do not change released versions, the release flow or
workflow permissions as a side effect. When an industry best practice would materially
improve the chart, explain the alternative and its trade-offs before applying it.
