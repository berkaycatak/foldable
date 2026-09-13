import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../model/foldable_data.dart';
import '../model/hinge_status.dart';
import '../model/reserved_region.dart';
import '../model/size_class.dart';

/// The facets of [FoldableData] a widget can depend on individually.
enum FoldableAspect {
  /// Platform support and diagnostics.
  capabilities,

  /// The fold posture.
  status,

  /// The continuous hinge angle.
  angle,

  /// Hardware-reserved regions.
  regions,

  /// The features bridged into `MediaQuery.displayFeatures`.
  displayFeatures,

  /// The iOS size classes.
  sizeClass,
}

/// Exposes fold state to the widget tree.
///
/// Inserted by `FoldableProvider`; you rarely construct this directly.
///
/// This is an [InheritedModel] rather than a plain [InheritedWidget] for one
/// reason: the hinge angle is a continuous signal. Without per-aspect
/// dependencies, every angle update would rebuild the entire subtree. A widget
/// reading [statusOf] is not disturbed while the angle sweeps.
///
/// Also aliased as `FoldableMediaQuery`, which is the name to prefer in code
/// meant to outlive any single device.
class DuoMediaQuery extends InheritedModel<FoldableAspect> {
  /// Creates a fold-state scope.
  const DuoMediaQuery({super.key, required this.data, required super.child});

  /// The current fold state.
  final FoldableData data;

  /// The fold state, or [FoldableData.unsupported] when there is no provider.
  ///
  /// Never throws: a device without a hinge legitimately has no provider, and
  /// widgets should keep working.
  static FoldableData of(BuildContext context) =>
      maybeOf(context) ?? FoldableData.unsupported;

  /// The fold state, or `null` when there is no provider above [context].
  static FoldableData? maybeOf(BuildContext context) =>
      InheritedModel.inheritFrom<DuoMediaQuery>(context)?.data;

  /// The fold posture, rebuilding the caller only when the posture changes.
  static HingeStatus statusOf(BuildContext context) =>
      InheritedModel.inheritFrom<DuoMediaQuery>(
        context,
        aspect: FoldableAspect.status,
      )?.data.status ??
      HingeStatus.unknown;

  /// The hinge angle in degrees, rebuilding the caller when it moves by more
  /// than [angleRebuildThresholdDegrees].
  ///
  /// For smooth, per-frame effects prefer `Foldable.hingeAngleStream`, which
  /// bypasses the element tree entirely.
  static double? angleOf(BuildContext context) =>
      InheritedModel.inheritFrom<DuoMediaQuery>(
        context,
        aspect: FoldableAspect.angle,
      )?.data.angleDegrees;

  /// Hardware-reserved regions, rebuilding the caller only when they change.
  static List<ReservedRegion> regionsOf(BuildContext context) =>
      InheritedModel.inheritFrom<DuoMediaQuery>(
        context,
        aspect: FoldableAspect.regions,
      )?.data.regions ??
      const <ReservedRegion>[];

  /// The horizontal size class iOS reports, rebuilding only when it changes.
  ///
  /// This is the signal iOS lays out from, and unlike a width breakpoint it
  /// also tracks Split View. Available on every iOS device, not just foldables.
  static SizeClass horizontalSizeClassOf(BuildContext context) =>
      InheritedModel.inheritFrom<DuoMediaQuery>(
        context,
        aspect: FoldableAspect.sizeClass,
      )?.data.horizontalSizeClass ??
      SizeClass.unspecified;

  /// The vertical size class iOS reports, rebuilding only when it changes.
  static SizeClass verticalSizeClassOf(BuildContext context) =>
      InheritedModel.inheritFrom<DuoMediaQuery>(
        context,
        aspect: FoldableAspect.sizeClass,
      )?.data.verticalSizeClass ??
      SizeClass.unspecified;

  /// Whether the device has a hinge, rebuilding only when that changes.
  static bool isFoldableOf(BuildContext context) =>
      InheritedModel.inheritFrom<DuoMediaQuery>(
        context,
        aspect: FoldableAspect.capabilities,
      )?.data.isFoldable ??
      false;

  /// How far the angle must move, in degrees, before [angleOf] dependents
  /// rebuild.
  static const double angleRebuildThresholdDegrees = 0.5;

  @override
  bool updateShouldNotify(DuoMediaQuery oldWidget) => data != oldWidget.data;

  @override
  bool updateShouldNotifyDependent(
    DuoMediaQuery oldWidget,
    Set<FoldableAspect> dependencies,
  ) {
    final FoldableData old = oldWidget.data;
    return dependencies.any(
      (FoldableAspect aspect) => switch (aspect) {
        FoldableAspect.capabilities => data.capabilities != old.capabilities,
        FoldableAspect.status => data.status != old.status,
        FoldableAspect.angle => _angleChanged(
          data.angleDegrees,
          old.angleDegrees,
        ),
        // Compared with listEquals, not `!=`. MediaQuery itself compares its
        // display feature list by identity, which makes a freshly built list
        // rebuild every dependent each frame; this does not repeat that.
        FoldableAspect.regions => !listEquals(data.regions, old.regions),
        FoldableAspect.displayFeatures => !listEquals(
          data.displayFeatures,
          old.displayFeatures,
        ),
        FoldableAspect.sizeClass =>
          data.horizontalSizeClass != old.horizontalSizeClass ||
              data.verticalSizeClass != old.verticalSizeClass,
      },
    );
  }

  static bool _angleChanged(double? current, double? previous) {
    if (current == null || previous == null) return current != previous;
    return (current - previous).abs() > angleRebuildThresholdDegrees;
  }
}

/// Device-agnostic name for [DuoMediaQuery].
///
/// Prefer this in code that should read naturally on future foldable hardware.
typedef FoldableMediaQuery = DuoMediaQuery;
