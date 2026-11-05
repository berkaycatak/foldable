/// Where the system places its vertical bar for this window.
///
/// Mirrors `UITraitCollection.verticalBarEdge` (iOS 27.1). On iPhone Duo the
/// system moves toolbars and tab bars into a vertical bar on the outer display
/// and on the inner display in landscape. UIKit reports the edge as leading or
/// trailing; the native side resolves it against the layout direction, so this
/// is the **physical** side, the one the bar is aligned to in every language.
///
/// The trait reflects the system's preferred edge whether or not a vertical
/// bar is visible, so an app drawing its own bars can follow it.
enum VerticalBarEdge {
  /// The system uses no vertical bar here: hardware without one, or a size
  /// class or orientation that keeps horizontal bars, such as the iPhone Duo
  /// inner display in portrait.
  none('none'),

  /// The vertical bar sits on the left edge of the window.
  left('left'),

  /// The vertical bar sits on the right edge of the window.
  right('right'),

  /// No reading: not iOS, iOS older than 27.1, or no reading has arrived.
  unknown('unknown');

  const VerticalBarEdge(this.wireName);

  /// The identifier used on the platform channel.
  final String wireName;

  /// Decodes a wire value, falling back to [unknown].
  static VerticalBarEdge fromWire(Object? value) => switch (value) {
    'none' => VerticalBarEdge.none,
    'left' => VerticalBarEdge.left,
    'right' => VerticalBarEdge.right,
    _ => VerticalBarEdge.unknown,
  };
}
