# foldable

**iPhone Duo support for Flutter.** Hinge angle, fold posture and fold/camera
display regions on Apple's foldable iPhone.

iPhone Duo was announced on 9 September 2026 and goes on sale 23 October 2026.
It ships with iOS 27, has a 7.6" inner display and a 5.4" cover display, and
its hinge APIs arrive in the iOS 27.1 SDK.

Flutter does not populate `MediaQuery.displayFeatures` on iOS. `dart:ui` states
outright that display features are *"populated only on Android"*, so none of
this information reaches a Flutter app running on iPhone Duo. This package
bridges it over a platform channel.

**Safe to depend on unconditionally.** It compiles against iOS 13 and older
SDKs, adds nothing to your build on devices without a hinge, and by default
changes no framework behaviour whatsoever.

### What you get on iPhone Duo

- **Hinge angle** as a live stream, in degrees: `0°` folded shut, `180°` flat
- **Fold posture**: `closed` / `partiallyOpen` / `fullyOpen`, Apple's own terms
- **Fold and camera geometry**: where the iPhone Duo crease and the FaceTime
  camera fall, as Apple's `.division` and `.occlusion` reserved regions
- **Fold-aware layout**: `FoldAwareBuilder` plus an `InheritedModel` that
  rebuilds only the widgets that care about the fold
- **Optional** `MediaQuery.displayFeatures` bridging, off by default

## Install

```yaml
dependencies:
  foldable: ^0.1.0
```

## Use

Outside the widget tree:

```dart
if (await Foldable.isFoldable) {
  Foldable.hingeAngleStream.listen((double degrees) {
    // 0° folded shut, 180° flat
  });
  Foldable.hingeStatusStream.listen((HingeStatus status) {
    // closed / partiallyOpen / fullyOpen
  });
}
```

On any device that is not an iPhone Duo, `isFoldable` is `false` and every
stream completes without emitting, so a `StreamBuilder` lands on
`ConnectionState.done` rather than waiting forever.

Inside the widget tree, wrap once and read anywhere below:

```dart
FoldableProvider(
  child: MaterialApp(home: HomePage()),
)
```

```dart
FoldAwareBuilder(
  builder: (context, constraints, fold) {
    if (!fold.spansDivision) return const SinglePane();
    return Row(
      children: const [Expanded(child: Leading), Expanded(child: Trailing)],
    );
  },
)
```

Or read a single facet, rebuilding only on that facet:

```dart
final HingeStatus status = DuoMediaQuery.statusOf(context);
final double? angle = DuoMediaQuery.angleOf(context);
final FoldableData data = DuoMediaQuery.of(context);
```

`DuoMediaQuery` is an `InheritedModel`, so a widget reading the posture is not
disturbed while the angle sweeps. For per-frame effects, use
`Foldable.hingeAngleStream` directly and keep the element tree out of it. That
is also Apple's guidance for iPhone Duo: drive effects and interactions from
the raw angle, and drive layout from posture and size classes.

## The `MediaQuery` bridge is opt-in, and here is why

Flutter's `DisplayFeatureSubScreen` confines dialogs, bottom sheets, popup
menus and pickers to one side of any display feature it considers obstructing.
Eleven framework files inherit that behaviour.

On the iPhone Duo inner display, which is 626x890pt, publishing a 40pt fold
measures out as:

| Surface | Without bridging | With `full` |
|---|---|---|
| `AlertDialog` | 626pt wide | ~293pt |
| Modal bottom sheet | 626pt | ~293pt |
| `DatePickerDialog` | 626pt | ~293pt |

So this package **does not write to `MediaQuery.displayFeatures` by default**.
Merely adding a dependency must not change every Material surface in your app.

```dart
FoldableProvider(
  bridgeMode: DisplayFeatureBridgeMode.cutoutsOnly, // avoid the camera only
  child: ...,
)
```

| Mode | Effect |
|---|---|
| `none` *(default)* | Nothing published. Framework behaviour unchanged. |
| `cutoutsOnly` | Camera cutouts only. Surfaces keep full width. |
| `full` | Fold published too. Surfaces split, so have an `anchorPoint` plan. |

Regardless of mode, four invariants are enforced so this package can never
split your layout by accident:

- A zero-width region is never published. Combined with `postureHalfOpened` it
  would still satisfy `avoidBounds` and split the screen with *no visible
  fold*, and the iPhone Duo fold division is exactly zero-width while flat.
- Inactive regions are never published.
- Cutouts always carry `DisplayFeatureState.unknown`, which `dart:ui` asserts.
- Nothing is published while the device is closed, because the view is then on
  the cover display, which has no fold.

If Flutter itself starts reporting display features on iOS
([#192515](https://github.com/flutter/flutter/issues/192515)), the bridge
stands down automatically so the fold is never published twice.

## How this works before Xcode 27.1

The iPhone Duo hinge APIs, `UIHingeInteraction`, `hinge.status`, `hinge.angle`
and `view.reservedRegions(kind:)`, ship in the **iOS 27.1 SDK**. Apple has not
published reference documentation for them yet; everything known comes from
Tech Talks 111461 to 111466.

Naming those types in Swift would raise the required toolchain for everyone and
push the deployment target to iOS 27. Instead this package resolves them
through the Objective-C runtime:

- No iOS 27 type appears in Swift source, so old SDKs compile it fine.
- Deployment target stays at **iOS 13.0**.
- Selector spellings are not only guessed. When the candidate list misses, the
  real selector is **discovered** from the runtime.
- Conformance is checked with `class_conformsToProtocol` before anything is
  handed to `addInteraction`, and every KVC read is gated on the property
  actually existing.
- A wrong guess turns the feature off. It does not crash.

Five strategies are tried in order, namely change handler, delegate, KVO,
per-frame polling and notifications, and whichever one worked is reported back:

```dart
final caps = await Foldable.capabilities;
print(caps.strategy);          // e.g. interactionKVO
print(caps.angleUnitVerified); // false until confirmed on real hardware
```

When Xcode 27.1 is available, uncomment one line in `Package.swift` and one in
the podspec to compile `NativeSources.swift` against the real types. **The Dart
API does not change.** The runtime path stays as the fallback for anyone still
on an older toolchain.

## Help confirm the real iPhone Duo API

If you have an iPhone Duo, this is the most useful thing you can contribute:

```dart
final dump = await Foldable.debugDumpNativeApi();
```

It returns the real selectors, properties and delegate signatures from the
device. The example app has an **API dump** screen that shows it. Please open
an issue with the output.

## Not yet verified

Honest about what is still guesswork until an iPhone Duo is in hand:

- `UIHingeInteraction`'s initialiser and delegate signatures
- The Objective-C selector for `reservedRegions(kind:options:)`, and the raw
  values of `kind` and `options`
- The unit and zero point of `hinge.angle`. Readings are normalised to degrees
  and flagged with `angleUnitVerified: false`
- The real thickness and position of the iPhone Duo fold division
- How the Flutter view behaves when the device closes and moves to the cover
  display

Everything above degrades to "no fold reported", never to a crash.

## Scope

iOS only in 0.1, because that is where the gap is. On every other platform
`isFoldable` is `false` and the streams are empty, so the package is harmless
in a cross-platform app. Android foldables already get display features from
Flutter itself, and reading them needs no plugin.

There is deliberately no `TwoPane` widget. `NavigationSplitView`-style layouts
are already served by `LayoutBuilder` plus the fold geometry this package
provides, and Apple's guidance for iPhone Duo is explicitly *"don't design a
custom layout for each pose."*
