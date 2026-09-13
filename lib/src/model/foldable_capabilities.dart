import 'package:flutter/foundation.dart';

/// How much foldable support is actually available on the running device.
enum FoldableSupportLevel {
  /// Not iOS, an iOS version without the hinge APIs, or the symbols were not
  /// found at runtime.
  unsupported('unsupported'),

  /// The hinge APIs exist, but this device has no hinge. Apple reports
  /// `context.hinge == nil`.
  availableNoHinge('availableNoHinge'),

  /// The hinge APIs exist and this device has a hinge.
  available('available'),

  /// The native side did not answer.
  unknown('unknown');

  const FoldableSupportLevel(this.wireName);

  /// The identifier used on the platform channel.
  final String wireName;

  /// Decodes a wire value, falling back to [unknown].
  static FoldableSupportLevel fromWire(Object? value) => switch (value) {
    'unsupported' => FoldableSupportLevel.unsupported,
    'availableNoHinge' => FoldableSupportLevel.availableNoHinge,
    'available' => FoldableSupportLevel.available,
    _ => FoldableSupportLevel.unknown,
  };
}

/// What the platform can tell us, plus diagnostics about *how* it told us.
///
/// The diagnostic fields matter because Apple has not published reference
/// documentation for `UIHingeInteraction` yet: the native side resolves the
/// API through the Objective-C runtime and reports which path succeeded, so
/// problems in the field are debuggable without a device in hand.
@immutable
class FoldableCapabilities {
  /// Creates a capability report.
  const FoldableCapabilities({
    required this.supportLevel,
    required this.isFoldable,
    required this.hingeApiPresent,
    required this.regionApiPresent,
    required this.angleUnitVerified,
    required this.strategy,
  });

  /// Everything off. The value used on non-iOS platforms, on older iOS
  /// versions, and whenever the plugin is not reachable.
  static const FoldableCapabilities unsupported = FoldableCapabilities(
    supportLevel: FoldableSupportLevel.unsupported,
    isFoldable: false,
    hingeApiPresent: false,
    regionApiPresent: false,
    angleUnitVerified: false,
    strategy: 'none',
  );

  /// Overall support level.
  final FoldableSupportLevel supportLevel;

  /// Whether this device physically has a hinge.
  final bool isFoldable;

  /// Whether the hinge API symbol (`UIHingeInteraction`) was found.
  ///
  /// Tracked separately from [regionApiPresent] because the two APIs may ship
  /// in different iOS releases; a single flag would lose that distinction.
  final bool hingeApiPresent;

  /// Whether the reserved-region selector was found on `UIView`.
  final bool regionApiPresent;

  /// Whether the angle unit conversion has been confirmed against real
  /// hardware. While `false`, treat the angle as approximate.
  final bool angleUnitVerified;

  /// Which native resolution strategy produced the readings, for diagnostics.
  final String strategy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldableCapabilities &&
          other.supportLevel == supportLevel &&
          other.isFoldable == isFoldable &&
          other.hingeApiPresent == hingeApiPresent &&
          other.regionApiPresent == regionApiPresent &&
          other.angleUnitVerified == angleUnitVerified &&
          other.strategy == strategy;

  @override
  int get hashCode => Object.hash(
    supportLevel,
    isFoldable,
    hingeApiPresent,
    regionApiPresent,
    angleUnitVerified,
    strategy,
  );

  @override
  String toString() =>
      'FoldableCapabilities(${supportLevel.name}, isFoldable: $isFoldable, '
      'hingeApi: $hingeApiPresent, regionApi: $regionApiPresent, '
      'angleVerified: $angleUnitVerified, strategy: $strategy)';
}
