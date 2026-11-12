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
- `.github/workflows/claude.yml`: runs Claude Code when the repository owner mentions
  `@claude` in an issue or PR.
- `.github/workflows/image-versions.yml` + `.github/scripts/image-versions.sh`: comments the
  application versions behind changed `latest@sha256:...` pins (PostgreSQL/Redis) on
  Renovate PRs, because the PR itself only shows two digests.
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
- Renovate bumps the chart version in the same PR as every subchart, image or
  `appVersion` update (`bumpVersions` in `renovate.json`): major for a major update,
  patch for everything else. A dependency major becomes a chart major so that deploying
  repositories get a major update PR, which they do not automerge. For a manual change:
  patch for fixes, minor for new values, major for breaking value changes.
- CI (`chart-version` job, `.github/scripts/check-chart-version.sh`) fails a PR that
  changes what the chart renders (values, templates, `Chart.lock`, `Chart.yaml` other
  than `version:`) while its version is already released, or whose version is lower
  than the newest release.
- Keep the version references in `README.md` (install, ArgoCD and subchart examples,
  dependency table) in sync with `Chart.yaml`.

## Reviewing dependency update PRs

When asked about a Renovate PR (for example whether it contains breaking changes):

1. Cover every version between the old and the new one, not only the newest. Renovate PR
   bodies can be truncated, so read the upstream release notes and upgrade guides as well.
2. Check the findings against this chart: removed or renamed environment variables,
   ports, paths, user IDs, health checks, required PostgreSQL or Redis versions, database
   migrations, and whether a rollback is possible. Compare with `values.yaml` and
   `templates/`.
3. Render the chart for the PR and for the base branch and diff the output (see
   "Validation expectations").
4. Start the answer with the verdict. List each finding with its upstream link, the
   affected file or value, the effect on existing installations and the required action.
   Say what you could not verify; "nothing found" only covers what you actually read.
5. Commit a fix only when the comment asks for one, and keep it to what the update needs.
   Renovate already bumps the chart version (see "Releases"); raise it further only if
   the fix itself calls for more. Say in the PR that Renovate treats the branch as edited: it may stop updating it,
   and requesting a rebase through Renovate discards the extra commits.

## Conventions to preserve

- Everything site-specific stays configurable through `values.yaml`; defaults must work
  in a plain cluster.
- Images are set in `values.yaml` (`repository` + `tag`) so Renovate's helm-values manager
  can track them; do not hardcode images in templates.
- Every image is pinned: an exact version tag (`2.20.15`, not `2.20` or `latest`), or for
  images that only publish `latest` (Bitnami `postgresql`/`redis`) the digest embedded in
  the tag (`latest@sha256:...`), which Renovate keeps up to date. Keep `appVersion` equal
  to the Paperless-ngx image tag.
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
  the release job on `main` and to the job in `claude.yml`.
- `image-versions.yml` is the second PR-triggered job with a write permission
  (`pull-requests: write`, only to post one comment). It uses `pull_request`, runs only for
  same-repository PRs opened by `renovate[bot]`, and passes the token only to the step that
  posts the comment. Keep those conditions, do not add other permissions, and keep the
  posted text built from validated values (a registry is external data).
- `claude.yml` is the other exception, and it holds because that job has no `pull_request`
  trigger and only starts for an `@claude` mention by the repository owner. Keep that
  owner check, do not add `allowed_bots` or `allowed_non_write_users`, and do not give it
  registry logins or `helm push`.
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
- **Gotenberg stays on 8.x.** Gotenberg 9 removed the `/forms/pdfengines/*` routes and renamed
  post-processing fields (`pdfa` -> `nativePdfa`, stages). `gotenberg-client`, which
  Paperless-ngx uses, still calls the old API (also in Paperless 3.x), so email import and
  Office conversion would fail with 404/400. `renovate.json` pins `allowedVersions: "<9"`;
  lift it once Paperless ships a `gotenberg-client` with Gotenberg 9 support (see
  https://github.com/stumpylog/gotenberg-client/issues/149).
- The Bitnami `postgresql`/`redis` subcharts run `latest` images. With `IfNotPresent` the
  version depends on the node's cache; another node pulls today's `latest`. A PostgreSQL
  major change needs a data migration, so mention the current `latest` major in PRs that
  touch these images.

## Scope limit for agents

Only change what the task asks. Do not change released versions, the release flow or
workflow permissions as a side effect. When an industry best practice would materially
improve the chart, explain the alternative and its trade-offs before applying it.
