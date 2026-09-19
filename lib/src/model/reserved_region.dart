import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// The kind of screen area a [ReservedRegion] describes.
///
/// Mirrors Apple's `reservedRegions(kind:)` on `UIView` / `GeometryProxy`.
enum ReservedRegionKind {
  /// The fold itself, Apple's `.division`.
  ///
  /// A division *divides* the usable area without covering it: the display
  /// curves through the centre but keeps rendering. While the device is flat
  /// the division is inactive, so it is only returned when the platform is
  /// queried with `.includeInactive`. Its `isActive` flag lags the hinge, so
  /// prefer the posture when deciding whether a fold is in effect.
  division('division'),

  /// An area physically covered by hardware such as the FaceTime camera.
  /// Apple's `.occlusion`.
  occlusion('occlusion'),

  /// A kind this version of the package does not recognise.
  unknown('unknown');

  const ReservedRegionKind(this.wireName);

  /// The identifier used on the platform channel.
  final String wireName;

  /// Decodes a wire value, falling back to [unknown].
  static ReservedRegionKind fromWire(Object? value) => switch (value) {
    'division' => ReservedRegionKind.division,
    'occlusion' => ReservedRegionKind.occlusion,
    _ => ReservedRegionKind.unknown,
  };
}

/// A region of the display reserved by hardware: the fold, or a camera cutout.
///
/// [bounds] is expressed in logical pixels within the Flutter view's coordinate
/// space. On iOS a UIKit point maps 1:1 to a Flutter logical pixel, so no
/// `devicePixelRatio` scaling is applied anywhere in this package.
@immutable
class ReservedRegion {
  /// Creates a reserved region.
  const ReservedRegion({
    required this.kind,
    required this.bounds,
    required this.isActive,
  });

  /// What this region represents.
  final ReservedRegionKind kind;

  /// The area covered, in logical pixels.
  final Rect bounds;

  /// Whether the region currently affects layout.
  ///
  /// A [ReservedRegionKind.division] is inactive while the device is flat.
  /// Inactive regions are still reported, since Apple notes they support
  /// high-level decisions such as preferring an even number of grid columns,
  /// but they must never be bridged into `MediaQuery.displayFeatures`.
  final bool isActive;

  /// Whether this region would make Flutter's [DisplayFeatureSubScreen] split
  /// the screen, were it published to `MediaQuery.displayFeatures`.
  ///
  /// Mirrors the predicate in `display_feature_sub_screen.dart`.
  bool get wouldSplitLayout => isActive && bounds.shortestSide > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReservedRegion &&
          other.kind == kind &&
          other.bounds == bounds &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(kind, bounds, isActive);

  @override
  String toString() =>
      'ReservedRegion(${kind.name}, $bounds, active: $isActive)';
}
