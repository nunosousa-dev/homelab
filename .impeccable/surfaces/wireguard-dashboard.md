# WireGuard Dashboard

Mode: Operate. Extend the existing Grafana dashboard system; no new visual identity.
Audience: homelab operator checking peer traffic and monitoring health.

## Direction contract

THESIS: Distinguish a broken observation pipeline from a quiet VPN peer. No connected-user claims.

OWN-WORLD: Native Grafana typography, panel grid, selectors, legends and tables. Green/red mark collection health; blue/green distinguish traffic directions; peer colours stay consistent across charts.

STORY: Select a server and interface, check collection, compare peer bandwidth, inspect handshake ages and sampled traffic totals. Public-key metadata can add names later; addresses remain the fallback.

FIRST VIEWPORT: A compact six-stat status strip above two equal-width bandwidth plots. Peer inventory immediately follows, with timestamps converted to age and zero handshakes shown as Never seen. Historical totals and collector diagnostics sit below.

FORM: Extension of the established Grafana provisioning and native dashboard grid; seed: none (unavailable). This native extension uses no concept tournament.

FINISH: Document this ordinary native extension here. No PRODUCT.md, DESIGN.md, sidecar, shipping rasters, or new design-system tokens are required; preserve Grafana's established UI.

## Repair verification handoff

- Scope: `kubernetes/bootstrap/monitoring/dashboards/wireguard.json`, panel 9 only; `joinByField` on `peer_id` changed from `outerTabular` to `outer` in commit `3f498c7`. Local HEAD and origin/main point to that commit; push and live verification are reported by the handoff.
- System unchanged: native Grafana palette, typography, panel grid, selectors, legends, tables and controls; no new palette, fonts or tokens.
- Desktop visual evidence inspected: `/tmp/wireguard-dashboard-check.833ndx/desktop.png` shows exactly three peer rows, each with VPN addresses, handshake age or Never seen, both byte counters and a fingerprint; no Unknown cells. Fingerprint presence is established, not full-key readability.
- Browser assertions reported by the handoff pass desktop and mobile row uniqueness and completeness; they were not rerun during this documentation pass.
- Mobile evidence inspected: `/tmp/wireguard-dashboard-check.833ndx/mobile.png` is a valid 390px viewport scrolled near inventory, but its rows are below the image. Mobile inventory readability is not visually approved.
- Stable live verification requires GitOps: Argo self-healing restores manually changed tracked ConfigMaps. Do not rely on manual ConfigMap changes persisting.
- Verdict: desktop inventory repair visually verified; mobile structural assertions reported passing, mobile visual approval outstanding. This note does not approve the whole dashboard or canonize existing UI drift; no UI repairs were made in this documentation pass.