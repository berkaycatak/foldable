/// High-level fold posture of the device hinge.
///
/// Mirrors the three states Apple reports through `UIHingeInteraction` /
/// `onHingeChange` on iPhone Duo: `.closed`, `.partiallyOpen` and `.fullyOpen`.
enum HingeStatus {
  /// The device is folded shut. On iPhone Duo the Flutter view is typically
  /// running on the outer display in this posture.
  ///
  /// There is deliberately no counterpart in `dart:ui`: [DisplayFeatureState]
  /// only defines `unknown`, `postureFlat` and `postureHalfOpened`. See
  /// `DisplayFeatureBridge` for how this is handled.
  closed('closed'),

  /// The hinge rests somewhere between closed and flat. Apple's
  /// `.partiallyOpen`, equivalent to `DisplayFeatureState.postureHalfOpened`.
  partiallyOpen('partiallyOpen'),

  /// The device is fully unfolded and the screen is flat. Apple's
  /// `.fullyOpen`, equivalent to `DisplayFeatureState.postureFlat`.
  fullyOpen('fullyOpen'),

  /// The device has no hinge, no reading has arrived yet, or the platform
  /// reported a posture this version of the package does not know about.
  ///
  /// Having this member means a future fourth Apple posture cannot break
  /// exhaustive `switch` statements in user code, and does not force a
  /// breaking change on this enum.
  unknown('unknown');

  const HingeStatus(this.wireName);

  /// The identifier used on the platform channel.
  final String wireName;

  /// Decodes a wire value, falling back to [unknown] for anything unexpected.
  static HingeStatus fromWire(Object? value) => switch (value) {
    'closed' => HingeStatus.closed,
    'partiallyOpen' => HingeStatus.partiallyOpen,
    'fullyOpen' => HingeStatus.fullyOpen,
    _ => HingeStatus.unknown,
  };
}
