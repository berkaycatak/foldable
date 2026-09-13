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
