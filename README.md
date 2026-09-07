# Paperless-ngx Helm Chart

A generic, configurable Helm chart for deploying [Paperless-ngx](https://docs.paperless-ngx.com/)
on Kubernetes. It has no dependency on any particular secret manager, cloud
provider, or cluster topology, so it can be reused as-is or wrapped by a
site-specific chart.

Published as an OCI artifact to `oci://ghcr.io/dominik-ba/charts/paperless`.

## About this chart

This is the **official** Paperless chart without any organization-specific
customizations. It's designed to be:

- **Reusable**: use directly in any Kubernetes cluster
- **Simple**: minimal dependencies, clear configuration
- **Flexible**: supports multiple secret management strategies
- **Composable**: can be used as a subchart in wrapper charts (e.g. with
  1Password integration)

## Features

- Uses the Bitnami PostgreSQL and Redis subcharts (low maintenance, regular
  updates)
- Flexible secret management (external secret or chart-created)
- Flexible persistence (StorageClass or static PV/PVC for SMB/NFS)
- Optional Gotenberg and Tika for document conversion
- Traefik-compatible ingress with path-based routing
- Common environment variables exposed in values

## Installation

```bash
helm install paperless oci://ghcr.io/dominik-ba/charts/paperless \
  --version 0.2.0 \
  --namespace paperless \
  --create-namespace
```

### Prerequisites

1. Kubernetes cluster with Helm 3.x
2. Storage provisioner (StorageClass) or pre-created PV/PVC for data persistence
3. For secrets: either create a Secret externally, or set `secrets.create=true`

#### Option 1: With an external secret (recommended)

```bash
kubectl create secret generic paperless-secret \
  --from-literal=PAPERLESS_ADMIN_USER=admin \
  --from-literal=PAPERLESS_ADMIN_PASSWORD="YourSecurePassword123!" \
  --from-literal=PAPERLESS_SECRET_KEY="$(openssl rand -base64 32)" \
  -n paperless
```

#### Option 2: With a chart-created secret (testing only)

```bash
helm install paperless oci://ghcr.io/dominik-ba/charts/paperless \
  --version 0.2.0 \
  --namespace paperless --create-namespace \
  --set secrets.create=true \
  --set secrets.adminUser=admin \
  --set secrets.adminPassword="YourPassword" \
  --set secrets.secretKey="$(openssl rand -base64 32)"
```

Not recommended for production — secrets end up in the release's values/history.

### Upgrading

```bash
helm upgrade paperless oci://ghcr.io/dominik-ba/charts/paperless \
  --version <new-version> \
  --namespace paperless
```

## Configuration

See [values.yaml](values.yaml) for all available values with inline
documentation.

### Secrets

Choose one approach:

**External secret (recommended):**

```yaml
secrets:
  create: false           # Default: don't create a secret
  secretName: paperless-secret
```

**Chart-created secret (testing):**

```yaml
secrets:
  create: true
  secretName: paperless-secret
  adminUser: admin
  adminPassword: changeme
  secretKey: "<random-32-char-string>"
```

### Persistence volumes

All four volumes are optional — enable what you need:

```yaml
persistence:
  consume:                   # Incoming documents folder
    enabled: true
    storageClassName: standard
    size: 10Gi
    # OR use an existing claim: existingClaim: paperless-consume

  data:                      # Search index and app data
    enabled: true
    storageClassName: standard
    size: 20Gi

  media:                     # Stored document files (largest)
    enabled: true
    storageClassName: standard
    size: 100Gi

  export:                    # Exported documents
    enabled: true
    storageClassName: standard
    size: 10Gi
```

For SMB/NFS, use `existingClaim` instead of `storageClassName` — see
[examples/smb-static-pvcs.yaml](examples/smb-static-pvcs.yaml) for a worked
example (static PV/PVC via the [SMB CSI driver](https://github.com/kubernetes-csi/csi-driver-smb)):

```bash
kubectl apply -f examples/smb-static-pvcs.yaml
```

### Ingress

```yaml
ingress:
  enabled: true
  className: traefik
  hosts:
    - host: paperless.example.com
  tls:
    - secretName: paperless-tls
      hosts:
        - paperless.example.com
```

### Application settings

```yaml
paperless:
  url: "https://paperless.example.com"
  timeZone: "Europe/Berlin"
  ocrLanguage: "eng"
  ocrLanguages: "eng+deu"    # Multiple languages
```

### Document conversion (optional)

```yaml
gotenberg:
  enabled: true              # Office docs -> PDF

tika:
  enabled: true              # Text/metadata extraction
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

## Using this chart as a subchart

This chart is intentionally free of any site-specific configuration. To layer
that on top, create a small wrapper chart that depends on this one:

```yaml
# Chart.yaml
dependencies:
  - name: paperless
    version: "0.2.0"
    repository: "oci://ghcr.io/dominik-ba/charts"

# values.yaml
paperless:
  secrets:
    create: false
  paperless:
    url: "https://paperless.example.com"
  # ... more configuration
```

Then add whatever organization-specific features you need (1Password
integration, custom ingress, monitoring) in the wrapper. For a concrete
example of this pattern (1Password integration, fixed ingress host, SMB
storage), see the `paperless-app` wrapper chart in
[dominik-ba/my-raspi-cluster](https://github.com/dominik-ba/my-raspi-cluster/tree/main/gitops/helm/paperless-app),
which consumes this chart as an OCI dependency.

## Troubleshooting

**Secret not found:**
- Verify the secret exists: `kubectl get secret paperless-secret -n paperless`
- If using external secret management, make sure it created the secret
  before this chart is deployed

**PVC pending:**
- Check the StorageClass exists: `kubectl get storageclass`
- For static PVCs, ensure the PV exists and matches the PVC spec
- `kubectl describe pvc paperless-consume -n paperless`

**Can't access the UI:**
- `kubectl get ingress -n paperless`
- `kubectl get svc paperless -n paperless`
- `kubectl logs deployment/paperless -n paperless`

**Database connection failed:**
- `kubectl get pods -l app.kubernetes.io/name=postgresql -n paperless`
- `kubectl logs <postgres-pod> -n paperless`

**PostgreSQL fails with a permission error on SMB-backed storage:**

```
FATAL: data directory has invalid permissions
```

This happens when PostgreSQL's persistence uses a storage class with `0777`
permissions (typical for SMB shares meant for the document volumes). Use a
storage class with secure permissions (`dir_mode` <= `0750`, `file_mode` <=
`0640`) for `postgresql.primary.persistence.storageClass` instead, then
delete the PostgreSQL pod to reinitialize with correct permissions:

```bash
kubectl delete pod -l app.kubernetes.io/name=postgresql -n paperless
```

## Dependencies

| Chart | Version | Repository |
|---|---|---|
| postgresql | 18.8.17 | oci://registry-1.docker.io/bitnamicharts |
| redis | 28.0.15 | oci://registry-1.docker.io/bitnamicharts |

## CI/CD

| Workflow | Trigger | Purpose |
|---|---|---|
| [CI](.github/workflows/ci.yml) | PRs & pushes to `main` | Lint, multi-scenario template rendering, kubeconform validation |
| [Release](.github/workflows/release.yml) | Semver tags `v*.*.*` | Package and push OCI artifact to `ghcr.io`, cut a GitHub Release |

### Releasing a new version

1. Bump `version` in [Chart.yaml](Chart.yaml)
2. Commit and push to `main`; CI must pass
3. Tag the commit: `git tag v<version> && git push origin v<version>`
4. The release workflow packages and pushes
   `ghcr.io/dominik-ba/charts/paperless:<version>` and creates a GitHub
   Release with install/upgrade instructions

## Links

- [Paperless-ngx documentation](https://docs.paperless-ngx.com/)
- [Bitnami PostgreSQL chart](https://github.com/bitnami/charts/tree/main/bitnami/postgresql)
- [Bitnami Redis chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [SMB CSI driver](https://github.com/kubernetes-csi/csi-driver-smb)
- [External Secrets Operator](https://external-secrets.io/)
- [1Password Operator](https://developer.1password.com/docs/connect/get-started)
