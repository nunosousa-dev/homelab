# Pod 

| File | Pod-level added | Container-level added |
|---|---|---|
| server.yaml | `runAsNonRoot`, `seccompProfile` | `allowPrivilegeEscalation: false`, `capabilities.drop: ALL`, `runAsNonRoot`, `seccompProfile` |
| machine-learning.yaml | `runAsUser: 2000`, `runAsGroup: 2000`, `fsGroup: 2000`, `runAsNonRoot`, `seccompProfile` | same container-level fields |
| redis.yaml | `runAsUser: 999`, `runAsGroup: 999`, `fsGroup: 999`, `runAsNonRoot`, `seccompProfile` | same container-level fields |
| postgres.yaml | `runAsUser: 999`, `runAsGroup: 999`, `fsGroup: 999`, `runAsNonRoot`, `seccompProfile` | same container-level fields |

Next step is to run `helm upgrade --install` and verify all pods reach `Running`. If postgres fails with a permission error on PGDATA, that's the initContainer caveat from the plan — let me know and we can add that.

Made changes.