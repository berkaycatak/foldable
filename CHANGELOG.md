## 0.2.0

Adds the iOS size class bridge, and corrects the reserved-region documentation
against Apple's published Tech Talk material.

- **New:** `SizeClass` (`compact` / `regular` / `unspecified`), bridged from
  `traitCollection` and exposed through `FoldableData.horizontalSizeClass`,
  `DuoMediaQuery.horizontalSizeClassOf`, and `FoldInfo.isRegularWidth`. This is
  the signal iOS lays out from, and unlike a width breakpoint it tracks Split
  View, where the class changes without the device folding. Reported on every
  iOS device, so it is useful when `isFoldable` is false.
- `FoldableProvider` now re-reads the snapshot when the window changes shape,
  so size classes stay current without a hinge to drive the event stream.
- `DuoMediaQuery` gains a `sizeClass` aspect, so posture readers are not
  rebuilt when only the size class changes.
- **Docs:** an occlusion region is active only while that camera is in use, and
  the fold division only while the device is folded. Both were already handled
  correctly in code through `isActive`; only the documentation was misleading.
- **Docs:** an app must be built against the iOS 27.1 SDK for reserved regions
  to exist at all. Hinge angle and posture are unaffected.
- **Docs:** note Apple's iOS 27.1 Arrangements API and why this package does
  not mirror it.

No breaking changes. Hinge readings remain unverified against physical
hardware; `FoldableCapabilities.angleUnitVerified` still reports `false`.

## 0.1.0

First release, published ahead of the iPhone Duo's 23 October 2026 launch.

- `Foldable.isFoldable`, `hingeAngleStream` (degrees), `hingeStatusStream`,
  `hingeStatus`, `snapshot`, `changes` and `capabilities`.
- `HingeStatus`: `closed` / `partiallyOpen` / `fullyOpen` / `unknown`,
  following Apple's own terminology.
- `FoldableProvider` + `DuoMediaQuery` (an `InheritedModel`, so the posture and
  the continuously changing angle rebuild independently) and `FoldAwareBuilder`.
- Opt-in `MediaQuery.displayFeatures` bridging via `DisplayFeatureBridgeMode`,
  **off by default**, with invariants that prevent an accidental layout split.
  See flutter/flutter#192515.
- iOS implementation resolves the iOS 27.1 hinge APIs through the Objective-C
  runtime, so the package compiles on older SDKs at an iOS 13.0 deployment
  target and no-ops safely on devices without a hinge.
- `Foldable.debugDumpNativeApi()` for confirming the real API shape on
  hardware.

Hinge readings have not been verified against a physical device;
`FoldableCapabilities.angleUnitVerified` reports `false` until they are.
