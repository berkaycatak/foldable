import 'dart:ui' show Rect;

import '../model/foldable_capabilities.dart';
import '../model/foldable_data.dart';
import '../model/hinge_status.dart';
import '../model/reserved_region.dart';

/// Decodes platform channel payloads into models.
///
/// Every field is read defensively. The standard method codec transmits whole
/// numbers as integers, so an angle that happens to land on exactly 90 arrives
/// as `int` and a plain `as double` cast would throw at runtime, hence
/// `(value as num?)?.toDouble()` everywhere.
abstract final class FoldableCodec {
  /// The wire schema version this package speaks.
  static const int wireVersion = 1;

  /// Decodes a snapshot payload. Returns [FoldableData.unsupported] for a
  /// `null` or malformed map rather than throwing.
  static FoldableData decodeSnapshot(Map<Object?, Object?>? raw) {
    if (raw == null) return FoldableData.unsupported;

    return FoldableData(
      capabilities: FoldableCapabilities(
        supportLevel: FoldableSupportLevel.fromWire(raw['supportLevel']),
        isFoldable: _bool(raw['isFoldable']),
        hingeApiPresent: _bool(raw['hingeApiPresent']),
        regionApiPresent: _bool(raw['regionApiPresent']),
        angleUnitVerified: _bool(raw['angleUnitVerified']),
        strategy: raw['strategy'] as String? ?? 'none',
      ),
      status: HingeStatus.fromWire(raw['status']),
      angleDegrees: _double(raw['angleDegrees']),
      regions: _regions(raw['regions']),
      // Bridging is a pure-Dart decision; the platform never supplies these.
      displayFeatures: const [],
    );
  }

  static List<ReservedRegion> _regions(Object? raw) {
    if (raw is! List) return const <ReservedRegion>[];

    final List<ReservedRegion> out = <ReservedRegion>[];
    for (final Object? entry in raw) {
      if (entry is! Map) continue;
      final double? left = _double(entry['left']);
      final double? top = _double(entry['top']);
      final double? width = _double(entry['width']);
      final double? height = _double(entry['height']);
      if (left == null || top == null || width == null || height == null) {
        continue;
      }
      out.add(
        ReservedRegion(
          kind: ReservedRegionKind.fromWire(entry['kind']),
          // Points map 1:1 to logical pixels on iOS, so no scaling.
          bounds: Rect.fromLTWH(left, top, width, height),
          isActive: _bool(entry['active']),
        ),
      );
    }
    return List<ReservedRegion>.unmodifiable(out);
  }

  static bool _bool(Object? value) => value is bool ? value : false;

  static double? _double(Object? value) => (value as num?)?.toDouble();
}
