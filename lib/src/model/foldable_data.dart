import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';

import 'foldable_capabilities.dart';
import 'hinge_status.dart';
import 'reserved_region.dart';

/// An atomic snapshot of everything the platform knows about the fold.
///
/// The native side emits one of these per change rather than separate streams
/// for posture, angle and geometry, so consumers can never observe an
/// inconsistent intermediate state (a `fullyOpen` status alongside the regions
/// of a half-open device).
@immutable
class FoldableData {
  /// Creates a snapshot.
  const FoldableData({
    required this.capabilities,
    required this.status,
    required this.angleDegrees,
    required this.regions,
    required this.displayFeatures,
  });

  /// The value used on devices without a hinge, on non-iOS platforms, and
  /// before the first reading arrives.
  static const FoldableData unsupported = FoldableData(
    capabilities: FoldableCapabilities.unsupported,
    status: HingeStatus.unknown,
    angleDegrees: null,
    regions: <ReservedRegion>[],
    displayFeatures: <DisplayFeature>[],
  );

  /// What the platform supports, and how it resolved the APIs.
  final FoldableCapabilities capabilities;

  /// The current fold posture.
  final HingeStatus status;

  /// The hinge angle in **degrees**: 0° fully closed, 180° fully flat.
  ///
  /// `null` when the device has no hinge or no reading has arrived.
  ///
  /// Apple has not documented the zero point of `hinge.angle`, so the native
  /// bridge normalises the value and reports
  /// [FoldableCapabilities.angleUnitVerified] alongside it. Until that flag is
  /// `true`, treat the reading as approximate.
  final double? angleDegrees;

  /// Hardware-reserved areas of the display: the fold and any camera cutouts.
  final List<ReservedRegion> regions;

  /// The subset of [regions] published to `MediaQuery.displayFeatures`.
  ///
  /// Always empty unless the surrounding `FoldableProvider` opted into
  /// bridging. See `DisplayFeatureBridgeMode`.
  final List<DisplayFeature> displayFeatures;

  /// Whether this device physically has a hinge.
  bool get isFoldable => capabilities.isFoldable;

  /// Whether the hinge currently rests between closed and flat.
  bool get isPartiallyOpen => status == HingeStatus.partiallyOpen;

  /// Whether the device is fully unfolded.
  bool get isFullyOpen => status == HingeStatus.fullyOpen;

  /// The active fold regions, ignoring camera cutouts and inactive folds.
  Iterable<ReservedRegion> get activeDivisions => regions.where(
    (ReservedRegion r) =>
        r.isActive && r.kind == ReservedRegionKind.division,
  );

  /// Returns a copy with the given fields replaced.
  FoldableData copyWith({
    FoldableCapabilities? capabilities,
    HingeStatus? status,
    double? angleDegrees,
    bool clearAngle = false,
    List<ReservedRegion>? regions,
    List<DisplayFeature>? displayFeatures,
  }) {
    return FoldableData(
      capabilities: capabilities ?? this.capabilities,
      status: status ?? this.status,
      angleDegrees: clearAngle ? null : (angleDegrees ?? this.angleDegrees),
      regions: regions ?? this.regions,
      displayFeatures: displayFeatures ?? this.displayFeatures,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldableData &&
          other.capabilities == capabilities &&
          other.status == status &&
          other.angleDegrees == angleDegrees &&
          listEquals(other.regions, regions) &&
          listEquals(other.displayFeatures, displayFeatures);

  @override
  int get hashCode => Object.hash(
    capabilities,
    status,
    angleDegrees,
    Object.hashAll(regions),
    Object.hashAll(displayFeatures),
  );

  @override
  String toString() =>
      'FoldableData(${status.name}, angle: $angleDegrees°, '
      'regions: ${regions.length}, features: ${displayFeatures.length})';
}
