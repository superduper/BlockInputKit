## AppKit Snapshot Tests

- Keep snapshot matrices minimal: prefer representative documents over one fixture per block kind.
- Make fixtures deterministic by pinning view size, appearance, accent color, and visible document content.
- Use `appKitSnapshotImage()` for AppKit image snapshot assertions so local Retina baselines and headless CI rendering stay comparable.
- Record new baselines intentionally with `./scripts/snapshots.sh record`; run it without filters after broad editor chrome or default inset changes so every snapshot baseline is refreshed, then verify with `./scripts/snapshots.sh verify`.
- Keep snapshot helpers local to this folder unless non-snapshot AppKit tests need them.
