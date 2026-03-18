# Paperless Helm Chart

A clean, reusable Helm chart for deploying [Paperless-ngx](https://docs.paperless-ngx.com/) - a document management system.

## About This Chart

This is the **official** Paperless chart without any organization-specific customizations. It's designed to be:

- **Reusable**: Use directly in any Kubernetes cluster
- **Simple**: Minimal dependencies, clear configuration
- **Flexible**: Supports multiple secret management strategies
- **Composable**: Can be used as a subchart in wrapper charts (e.g., with 1Password integration)

## Features

- ✅ Uses Bitnami PostgreSQL and Redis subcharts (low maintenance, regular updates)
- ✅ Flexible secret management (external secret or chart-created)
- ✅ Flexible persistence (StorageClass or static PV/PVC for SMB/NFS)
- ✅ Optional Gotenberg and Tika for document conversion
- ✅ Traefik ingress with path-based routing
- ✅ Common environment variables exposed in values

## Quick Start

### Prerequisites

1. Kubernetes cluster with Helm 3.x
2. Storage provisioner (StorageClass) or pre-created PV/PVC for data persistence
3. For secrets: Either create a Secret externally or set `secrets.create=true`

### Installation

#### Option 1: With External Secret (Recommended)

```bash
# 1. Create the secret (using kubectl, 1Password Operator, etc.)
kubectl create secret generic paperless-secret \
  --from-literal=PAPERLESS_ADMIN_USER=admin \
  --from-literal=PAPERLESS_ADMIN_PASSWORD="YourSecurePassword123!" \
  --from-literal=PAPERLESS_SECRET_KEY="$(openssl rand -base64 32)" \
  -n default

# 2. Update dependencies
helm dependency update

# 3. Install chart
helm install paperless . -n default --create-namespace
```

#### Option 2: With Chart-Created Secret (Testing Only)

```bash
helm dependency update

helm install paperless . -n default --create-namespace \
  --set secrets.create=true \
  --set secrets.adminUser=admin \
  --set secrets.adminPassword="YourPassword" \
  --set secrets.secretKey="$(openssl rand -base64 32)"
```

⚠️ **Not recommended for production** - secrets stored in values/history.

## Configuration

### Essential Settings

#### Secrets

Choose one approach:

**External Secret (Recommended):**

```yaml
secrets:
  create: false              # Default: don't create secret
  name: paperless-secret     # Reference existing secret
```

**Chart-Created Secret (Testing):**

```yaml
secrets:
  create: true
  name: paperless-secret
  adminUser: admin
  adminPassword: changeme
  secretKey: "<random-32-char-string>"
```

#### Persistence Volumes

All volumes optional, enable what you need:

```yaml
persistence:
  consume:                   # Incoming documents folder
    enabled: true
    storageClassName: standard
    size: 10Gi
    # OR use existing: existingClaim: paperless-consume
  
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

For SMB/NFS, use `existingClaim` instead of `storageClassName`.

#### Ingress

```yaml
ingress:
  enabled: true
  className: traefik
  entrypoint: web            # or websecure for HTTPS
  hosts:
    - host: paperless.yourdomain.local
      paths:
        - path: /
          pathType: Prefix
```

#### Application Settings

```yaml
paperless:
  url: "http://paperless.yourdomain.local"
  timeZone: "Europe/Berlin"
  ocrLanguage: "eng"
  ocrLanguages: "eng+deu"    # Multiple languages
```

#### Document Conversion (Optional)

```yaml
gotenberg:
  enabled: true              # For Office docs → PDF

tika:
  enabled: true              # For text extraction
```

### Complete Example: SMB Storage

```bash
# 1. Create static PVCs (if using SMB/NFS)
kubectl apply -f examples/smb-static-pvcs.yaml

# 2. Create secret
kubectl create secret generic paperless-secret \
  --from-literal=PAPERLESS_ADMIN_USER=admin \
  --from-literal=PAPERLESS_ADMIN_PASSWORD="SecurePass123!" \
  --from-literal=PAPERLESS_SECRET_KEY="$(openssl rand -base64 32)" \
  -n default

# 3. Install with existing PVCs
helm install paperless . -n default --create-namespace \
  --set persistence.consume.enabled=true \
  --set persistence.consume.existingClaim=paperless-consume \
  --set persistence.data.enabled=true \
  --set persistence.data.existingClaim=paperless-data \
  --set persistence.media.enabled=true \
  --set persistence.media.existingClaim=paperless-media \
  --set persistence.export.enabled=true \
  --set persistence.export.existingClaim=paperless-export
```

## Verification

```bash
# Check pods
kubectl -n default get pods

# Check PVCs
kubectl -n default get pvc

# Check logs
kubectl -n default logs deployment/paperless -f

# Port forward to access UI
kubectl -n default port-forward svc/paperless 8000:8000
# Open http://localhost:8000
```

## Verification & Troubleshooting

### Common Issues

**Secret not found:**

- Verify secret exists: `kubectl get secret paperless-secret -n default`
- If using external secret management, ensure it created the secret before deployment

**PVC pending:**

- Check StorageClass exists: `kubectl get storageclass`
- For static PVCs, ensure PV exists and matches PVC spec
- View PVC details: `kubectl describe pvc paperless-consume -n default`

**Can't access UI:**

- Check ingress: `kubectl get ingress -n default`
- Verify service: `kubectl get svc paperless -n default`
- Check pod logs: `kubectl logs deployment/paperless -n default`

**Database connection failed:**

- Verify PostgreSQL is running: `kubectl get pods -l app.kubernetes.io/name=postgresql -n default`
- Check PostgreSQL logs: `kubectl logs <postgres-pod> -n default`

**PostgreSQL permission denied on SMB:**

- Ensure using storage class with `dir_mode <= 0750`
- See PostgreSQL SMB section above

## Using with 1Password

For 1Password integration, use the **paperless-app** wrapper chart:

- See [../paperless-app/README.md](../paperless-app/README.md)
- The wrapper creates OnePasswordItem and delegates configuration to this chart

```yaml
# HTTP Ingress example
ingress:
  enabled: true
  className: traefik
  entrypoint: web
  hosts:
    - host: paperless.example.com
      paths:
      - path: /
        pathType: Prefix

```

### HTTPS with TLS

```yaml
ingress:
  enabled: true
  className: traefik
  entrypoint: websecure  # HTTPS
  annotations:
        - path: /
  hosts:
    - host: paperless.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: paperless-tls
      hosts:
        - paperless.example.com
```

## Troubleshooting & Support

### PostgreSQL Fails with Permission Error

**Symptom:**

```log
PostgreSQL pod fails to start with error:
FATAL: data directory has invalid permissions
```

**Cause:** Using a storage class with 0777 permissions for PostgreSQL (e.g., `qnap-smb`)

**Solution:** Use a secure storage class for PostgreSQL:

```yaml
postgresql:
  enabled: true
  primary:
    persistence:
      storageClassName: <correct-sc>  # Secure permissions (0750/0640)
      size: 50Gi
```

Then delete the PostgreSQL pod to reinitialize with correct permissions:

```bash
kubectl delete pod -l app.kubernetes.io/name=postgresql
```

If using a custom storage class, verify mount options:

- `dir_mode` must be 0750 or less (not 0777)
- `file_mode` must be 0640 or less (not 0777)

### Check Deployment Status

```bash
# Check pods
kubectl -n default get pods

# View logs
kubectl -n default logs deployment/paperless -f

# Describe deployment
kubectl -n default describe deployment paperless
```

### Verify Secret

```bash
# Check if secret exists
kubectl -n default get secret paperless-secret

# View secret keys
kubectl -n default get secret paperless-secret -o yaml
```

### Database Connection Issues

```bash
# Verify PostgreSQL is running
kubectl -n default get pods -l app.kubernetes.io/name=postgresql

# Test DB connection
kubectl -n default exec -it deployment/paperless -- \
  paperless-manage shell -c "from django.db import connection; connection.ensure_connection(); print('DB OK')"
```

### PVC Binding Issues

```bash
# Check PVCs
kubectl -n default get pvc

# Describe specific PVC
kubectl -n default describe pvc paperless-consume
```

## Using as a Subchart

This chart is designed to be reusable as a subchart. Example:

```yaml
# Chart.yaml
dependencies:
  - name: paperless
    version: "0.1.0"
    repository: "file://../paperless"

# values.yaml
paperless:
  secrets:
    create: false
  paperless:
    url: "http://paperless.local"
  postgresql:
    enabled: true
  # ... more configuration
```

Then create your own wrapper chart to add organization-specific features (e.g., 1Password integration, custom ingress, monitoring).

## Links

- [Paperless-ngx Documentation](https://docs.paperless-ngx.com/)
- [Bitnami PostgreSQL Chart](https://github.com/bitnami/charts/tree/main/bitnami/postgresql)
- [Bitnami Redis Chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [SMB CSI Driver](https://github.com/kubernetes-csi/csi-driver-smb)
- [External Secrets Operator](https://external-secrets.io/)
- [1Password Operator](https://developer.1password.com/docs/connect/get-started)
- [Paperless Wrapper Chart with 1Password](../paperless-app/README.md)
