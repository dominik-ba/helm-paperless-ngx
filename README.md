# paperless-ngx-helm

Helm chart for [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) — a document management system that transforms physical documents into a searchable online archive.

Published as an OCI artifact to `ghcr.io/dominik-ba/charts/paperless`.

## Installation

```bash
helm install paperless oci://ghcr.io/dominik-ba/charts/paperless \
  --version 0.2.0 \
  --namespace paperless \
  --create-namespace
```

## Upgrading

```bash
helm upgrade paperless oci://ghcr.io/dominik-ba/charts/paperless \
  --version <new-version> \
  --namespace paperless
```

## Chart Values

See [charts/paperless/values.yaml](charts/paperless/values.yaml) for all available values with inline documentation.

### Minimal configuration

```yaml
# secrets.create=true creates a Secret inline (dev/test only)
# In production use external secret management (1Password, External Secrets, etc.)
secrets:
  create: true
  secretName: paperless-secret
  adminUser: "admin"
  adminPassword: "changeme"
  secretKey: "change-me-to-random-string"

paperless:
  url: "https://paperless.example.com"
  timeZone: "Europe/Berlin"
```

### With SMB persistent storage

Create PVs using the example manifests in [charts/paperless/examples/smb-static-pvcs.yaml](charts/paperless/examples/smb-static-pvcs.yaml), then reference them:

```yaml
persistence:
  consume:
    enabled: true
    existingClaim: paperless-consume
  data:
    enabled: true
    existingClaim: paperless-data
  export:
    enabled: true
    existingClaim: paperless-export
  media:
    enabled: true
    existingClaim: paperless-media
```

### With Gotenberg and Tika (full document conversion)

```yaml
gotenberg:
  enabled: true

tika:
  enabled: true
```

## ArgoCD integration

Using the OCI chart directly in an ArgoCD `Application`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: paperless
  namespace: argocd
spec:
  destination:
    namespace: paperless
    server: https://kubernetes.default.svc
  project: default
  source:
    chart: paperless
    repoURL: ghcr.io/dominik-ba/charts
    targetRevision: 0.2.0
    helm:
      valueFiles:
        - values.yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

## Dependencies

| Chart | Version | Repository |
|---|---|---|
| postgresql | 18.5.7 | oci://registry-1.docker.io/bitnamicharts |
| redis | 25.3.5 | oci://registry-1.docker.io/bitnamicharts |

## CI/CD

| Workflow | Trigger | Purpose |
|---|---|---|
| [CI](.github/workflows/ci.yml) | PRs & pushes to `main` on `charts/**` | Lint, template rendering, kubeconform validation |
| [Release](.github/workflows/release.yml) | Semver tags `v*.*.*` | Package and push OCI artifact to `ghcr.io` |

### Releasing a new version

1. Bump `version` in [charts/paperless/Chart.yaml](charts/paperless/Chart.yaml)
2. Commit and push to `main`; CI must pass
3. Tag the commit: `git tag v<version> && git push origin v<version>`
4. The release workflow packages and pushes `ghcr.io/dominik-ba/charts/paperless:<version>`
