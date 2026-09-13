/// An iOS size class, the signal the system itself lays out from.
///
/// On iPhone Duo the cover display is [compact] width and the inner display is
/// [regular] width. Reading this is more reliable than guessing from a width
/// breakpoint, because it also accounts for Split View, where the app occupies
/// half the screen and the class changes without the device folding at all.
///
/// Available on every iOS device, not just foldables, so this is useful even
/// when [FoldableData.isFoldable] is false.
enum SizeClass {
  /// Narrow: a phone in portrait, or half of a Split View.
  compact('compact'),

  /// Wide: the iPhone Duo inner display, or an iPad.
  regular('regular'),

  /// Not reported, or not an iOS device.
  unspecified('unspecified');

  const SizeClass(this.wireName);

  /// The identifier used on the platform channel.
  final String wireName;

  /// Decodes a wire value, falling back to [unspecified].
  static SizeClass fromWire(Object? value) => switch (value) {
    'compact' => SizeClass.compact,
    'regular' => SizeClass.regular,
    _ => SizeClass.unspecified,
  };
}
