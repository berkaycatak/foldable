import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bridge/display_feature_bridge.dart';
import '../model/foldable_data.dart';
import '../platform/foldable_platform.dart';
import 'duo_media_query.dart';

/// Feeds fold state into the widget tree.
///
/// Place it above the widgets that need fold information, typically around
/// `MaterialApp`, or around the screen that adapts.
///
/// ```dart
/// FoldableProvider(
///   child: MaterialApp(home: HomePage()),
/// )
/// ```
class FoldableProvider extends StatefulWidget {
  /// Creates a provider.
  const FoldableProvider({
    super.key,
    required this.child,
    this.bridgeMode = DisplayFeatureBridgeMode.none,
    this.platform,
    this.debugData,
  });

  /// The subtree that can read fold state.
  final Widget child;

  /// Whether fold geometry is also published to `MediaQuery.displayFeatures`.
  ///
  /// Defaults to [DisplayFeatureBridgeMode.none], which leaves framework
  /// behaviour untouched.
  ///
  /// Turning this to [DisplayFeatureBridgeMode.full] makes Flutter confine
  /// dialogs, bottom sheets, popup menus and pickers to one side of the fold,
  /// roughly half of the 7.6" inner display. Measure your app before enabling
  /// it. See https://github.com/flutter/flutter/issues/192515.
  final DisplayFeatureBridgeMode bridgeMode;

  /// Overrides the platform implementation, for tests.
  final FoldablePlatform? platform;

  /// Drives the provider from a stream instead of the platform, for tests and
  /// for the example app's on-device simulator panel.
  final Stream<FoldableData>? debugData;

  @override
  State<FoldableProvider> createState() => _FoldableProviderState();
}

class _FoldableProviderState extends State<FoldableProvider> {
  FoldableData _data = FoldableData.unsupported;
  List<DisplayFeature> _features = const <DisplayFeature>[];
  StreamSubscription<FoldableData>? _subscription;
  AppLifecycleListener? _lifecycle;
  bool _warnedAboutUpstream = false;
  Size? _lastSize;

  FoldablePlatform get _platform => widget.platform ?? FoldablePlatform.instance;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Size classes change without the hinge moving: entering Split View,
    // rotating, or opening the device. The event stream only runs on hardware
    // that has a hinge, so the window size is what tells us to re-read them.
    final Size size = MediaQuery.sizeOf(context);
    if (_lastSize != null && size != _lastSize) {
      _refresh();
    }
    _lastSize = size;
  }

  @override
  void didUpdateWidget(FoldableProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.platform != oldWidget.platform ||
        widget.debugData != oldWidget.debugData) {
      _stop();
      _start();
    } else if (widget.bridgeMode != oldWidget.bridgeMode) {
      _apply(_data);
    }
  }

  void _start() {
    if (widget.debugData != null) {
      _subscription = widget.debugData!.listen(_apply);
      return;
    }

    // Capability detection goes through the one-shot query, never the stream:
    // EventChannel swallows activation failures, so a silent stream cannot be
    // told apart from a missing plugin.
    unawaited(
      _platform.getSnapshot().then((FoldableData snapshot) {
        if (!mounted) return;
        _apply(snapshot);
        // Without a hinge there is nothing to stream. Size classes still
        // arrive, refreshed from didChangeDependencies when the window
        // changes shape.
        if (!snapshot.isFoldable) return;
        _subscription = _platform.events.listen(_apply);
        _lifecycle = AppLifecycleListener(onResume: _refresh);
      }),
    );
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _refresh() {
    unawaited(
      _platform.getSnapshot().then((FoldableData snapshot) {
        if (mounted) _apply(snapshot);
      }),
    );
  }

  void _apply(FoldableData next) {
    final List<DisplayFeature> features = DisplayFeatureBridge.build(
      mode: _effectiveBridgeMode,
      regions: next.regions,
      status: next.status,
    );

    setState(() {
      // Keep the previous list instance when the contents are unchanged.
      // MediaQuery compares its display feature list by identity, so handing
      // it a fresh equal list every frame would rebuild every dependent.
      if (!listEquals(features, _features)) {
        _features = features;
      }
      _data = next.copyWith(displayFeatures: _features);
    });
  }

  /// The bridge mode actually in force.
  ///
  /// Falls back to [DisplayFeatureBridgeMode.none] once Flutter itself starts
  /// reporting display features on iOS, so the fold is never published twice.
  DisplayFeatureBridgeMode get _effectiveBridgeMode =>
      _upstreamProvidesFeatures
      ? DisplayFeatureBridgeMode.none
      : widget.bridgeMode;

  bool get _upstreamProvidesFeatures {
    if (!mounted) return false;
    // Reads the raw FlutterView, not our own MediaQuery override, so we never
    // mistake our own output for the engine's.
    return View.of(context).displayFeatures.isNotEmpty;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bridgeMode != DisplayFeatureBridgeMode.none &&
        _upstreamProvidesFeatures) {
      _warnAboutUpstreamOnce();
    }

    // The MediaQuery is always present, even with nothing to publish, so the
    // shape of the tree never changes. Inserting it only while there were
    // features remounted everything below on each fold and each change of
    // bridge mode, discarding scroll positions and State.
    final MediaQueryData ambient = MediaQuery.of(context);
    return MediaQuery(
      data: _features.isEmpty
          ? ambient
          : ambient.copyWith(displayFeatures: _features),
      child: DuoMediaQuery(data: _data, child: widget.child),
    );
  }

  void _warnAboutUpstreamOnce() {
    if (_warnedAboutUpstream) return;
    _warnedAboutUpstream = true;
    assert(() {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            'foldable: Flutter now reports display features on this platform, '
            'so bridgeMode was ignored to avoid publishing the fold twice.',
          ),
          library: 'foldable',
        ),
      );
      return true;
    }());
  }
}
