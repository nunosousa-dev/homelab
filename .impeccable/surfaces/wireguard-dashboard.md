# WireGuard Dashboard

Mode: Operate. Extend the existing Grafana dashboard system; no new visual identity.
Audience: homelab operator checking peer traffic and monitoring health.

## Direction contract

THESIS: Distinguish a broken observation pipeline from a quiet VPN peer. No connected-user claims.

OWN-WORLD: Native Grafana typography, panel grid, selectors, legends and tables. Green/red mark collection health; blue/green distinguish traffic directions; peer colours stay consistent across charts.

STORY: Select a server and interface, check collection, compare peer bandwidth, inspect handshake ages and sampled traffic totals. Public-key metadata can add names later; addresses remain the fallback.

FIRST VIEWPORT: A compact six-stat status strip above two equal-width bandwidth plots. Peer inventory immediately follows, with timestamps converted to age and zero handshakes shown as Never seen. Historical totals and collector diagnostics sit below.

FORM: Extension of the established Grafana provisioning and native dashboard grid; seed: none (established system).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance. No shipping rasters or new design-system tokens are needed for this extension.