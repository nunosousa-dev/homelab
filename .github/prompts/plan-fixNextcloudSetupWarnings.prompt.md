# Fix Nextcloud Setup Warnings

## Warnings being addressed

| Warning | Fix |
|---------|-----|
| No maintenance window configured | `occ config:system:set` in PostSync Job |
| Mimetype migrations available | `occ maintenance:repair --include-expensive` in PostSync Job |
| HSTS header not set | Traefik `Middleware` CRD + `ExtensionRef` on HTTPRoute |
| Missing optional indices | `occ db:add-missing-indices` in PostSync Job |
| No default phone region | `occ config:system:set default_phone_region` in PostSync Job |
| Email server not configured | Out of scope — requires SMTP credentials |

---

## Changes

### 1. `kubernetes/apps/nextcloud/values.yaml`

Add after `adminUser`:

```yaml
  adminUser: admin
  defaultPhoneRegion: PT
  maintenanceWindowStart: 1
```

---

### 2. `kubernetes/apps/nextcloud/templates/httproute.yaml`

Add `filters` block before `backendRefs`:

```yaml
    - matches:
        - path:
            type: PathPrefix
            value: /
      filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: nextcloud-headers
      backendRefs:
        - group: ""
          kind: Service
          name: nextcloud
          port: 80
          weight: 1
```

---

### 3. Create `kubernetes/apps/nextcloud/templates/traefik-middleware.yaml`

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: nextcloud-headers
  namespace: nextcloud
spec:
  headers:
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true
    contentTypeNosniff: true
    browserXssFilter: true
    customResponseHeaders:
      X-Frame-Options: "SAMEORIGIN"
      Referrer-Policy: "no-referrer"
```

---

### 4. Create `kubernetes/apps/nextcloud/templates/occ-job.yaml`

ArgoCD PostSync hook — runs after every sync, idempotent.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nextcloud-occ-setup
  namespace: nextcloud
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      securityContext:
        runAsUser: 33
        runAsGroup: 33
        fsGroup: 33
        fsGroupChangePolicy: OnRootMismatch
      containers:
        - name: occ
          image: {{ .Values.nextcloud.image }}
          command:
            - /bin/sh
            - -c
            - |
              set -e
              php /var/www/html/occ maintenance:repair --include-expensive --no-interaction
              php /var/www/html/occ db:add-missing-indices --no-interaction
              php /var/www/html/occ config:system:set maintenance_window_start \
                --value={{ .Values.nextcloud.maintenanceWindowStart }} --type=integer
              php /var/www/html/occ config:system:set default_phone_region \
                --value={{ .Values.nextcloud.defaultPhoneRegion }}
          volumeMounts:
            - name: nextcloud-data
              mountPath: /var/www/html
      volumes:
        - name: nextcloud-data
          persistentVolumeClaim:
            claimName: nextcloud-data
      restartPolicy: OnFailure
```

---

## Notes

- `traefik.io/v1alpha1` is the Traefik v3 API group. If on v2, change to `traefik.containo.us/v1alpha1`.
- `maintenanceWindowStart: 1` = 1 AM UTC. Adjust to your preferred low-traffic hour.
- The PostSync Job mounts the same `nextcloud-data` PVC — occ reads `config/config.php` from the already-initialized volume.
- After ArgoCD sync, check Job logs: `kubectl logs -n nextcloud job/nextcloud-occ-setup`
