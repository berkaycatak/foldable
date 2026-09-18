import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:foldable/foldable.dart';

void main() => runApp(const FoldableExampleApp());

/// Demonstrates the package, and doubles as a fold simulator so the layout
/// behaviour can be exercised on an ordinary iPhone simulator, where no
/// foldable device profile exists.
class FoldableExampleApp extends StatefulWidget {
  const FoldableExampleApp({super.key});

  @override
  State<FoldableExampleApp> createState() => _FoldableExampleAppState();
}

class _FoldableExampleAppState extends State<FoldableExampleApp> {
  final StreamController<FoldableData> _simulator =
      StreamController<FoldableData>.broadcast();

  bool _simulate = false;
  DisplayFeatureBridgeMode _bridgeMode = DisplayFeatureBridgeMode.none;
  HingeStatus _status = HingeStatus.fullyOpen;
  double _angle = 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushSimulated());
  }

  @override
  void dispose() {
    _simulator.close();
    super.dispose();
  }

  void _pushSimulated() {
    if (!_simulate || _simulator.isClosed) return;
    final Size size = MediaQuery.sizeOf(context);
    const double thickness = 40;

    _simulator.add(
      FoldableData(
        capabilities: const FoldableCapabilities(
          supportLevel: FoldableSupportLevel.available,
          isFoldable: true,
          hingeApiPresent: true,
          regionApiPresent: true,
          angleUnitVerified: false,
          strategy: 'simulated',
        ),
        status: _status,
        angleDegrees: _angle,
        regions: <ReservedRegion>[
          ReservedRegion(
            kind: ReservedRegionKind.division,
            bounds: Rect.fromLTWH(
              (size.width - thickness) / 2,
              0,
              thickness,
              size.height,
            ),
            // A fold is inactive, and zero-width, while the device is flat.
            isActive: _status == HingeStatus.partiallyOpen,
          ),
        ],
        displayFeatures: const <DisplayFeature>[],
        // Mirrors how iOS classifies width: the cover display is compact, the
        // inner display regular.
        horizontalSizeClass: size.width >= 600
            ? SizeClass.regular
            : SizeClass.compact,
        verticalSizeClass: SizeClass.regular,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'foldable',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: FoldableProvider(
        bridgeMode: _bridgeMode,
        debugData: _simulate ? _simulator.stream : null,
        child: _HomePage(
          simulate: _simulate,
          bridgeMode: _bridgeMode,
          status: _status,
          angle: _angle,
          onSimulateChanged: (bool value) {
            setState(() => _simulate = value);
            _pushSimulated();
          },
          onBridgeModeChanged: (DisplayFeatureBridgeMode mode) =>
              setState(() => _bridgeMode = mode),
          onStatusChanged: (HingeStatus status) {
            setState(() {
              _status = status;
              _angle = switch (status) {
                HingeStatus.closed => 0,
                HingeStatus.partiallyOpen => 95,
                HingeStatus.fullyOpen => 180,
                HingeStatus.unknown => _angle,
              };
            });
            _pushSimulated();
          },
          onAngleChanged: (double angle) {
            setState(() {
              _angle = angle;
              _status = angle <= 5
                  ? HingeStatus.closed
                  : angle >= 175
                  ? HingeStatus.fullyOpen
                  : HingeStatus.partiallyOpen;
            });
            _pushSimulated();
          },
        ),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.simulate,
    required this.bridgeMode,
    required this.status,
    required this.angle,
    required this.onSimulateChanged,
    required this.onBridgeModeChanged,
    required this.onStatusChanged,
    required this.onAngleChanged,
  });

  final bool simulate;
  final DisplayFeatureBridgeMode bridgeMode;
  final HingeStatus status;
  final double angle;
  final ValueChanged<bool> onSimulateChanged;
  final ValueChanged<DisplayFeatureBridgeMode> onBridgeModeChanged;
  final ValueChanged<HingeStatus> onStatusChanged;
  final ValueChanged<double> onAngleChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('foldable'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Native API dump',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _DumpPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const _DeviceCard(),
          const SizedBox(height: 16),
          const _AngleCard(),
          const SizedBox(height: 16),
          const _FoldAwareCard(),
          const SizedBox(height: 16),
          _BridgeCard(
            bridgeMode: bridgeMode,
            onChanged: onBridgeModeChanged,
          ),
          const SizedBox(height: 16),
          _SimulatorCard(
            simulate: simulate,
            status: status,
            angle: angle,
            onSimulateChanged: onSimulateChanged,
            onStatusChanged: onStatusChanged,
            onAngleChanged: onAngleChanged,
          ),
        ],
      ),
    );
  }
}

/// What the platform reports about this device.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context) {
    final FoldableData data = DuoMediaQuery.of(context);
    final FoldableCapabilities caps = data.capabilities;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Device', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _Row('isFoldable', '${data.isFoldable}'),
            _Row('support', caps.supportLevel.name),
            _Row('status', data.status.name),
            _Row('strategy', caps.strategy),
            _Row('hinge API', '${caps.hingeApiPresent}'),
            _Row('region API', '${caps.regionApiPresent}'),
            _Row('angle verified', '${caps.angleUnitVerified}'),
            _Row('regions', '${data.regions.length}'),
            _Row('size class H', data.horizontalSizeClass.name),
            _Row('size class V', data.verticalSizeClass.name),
          ],
        ),
      ),
    );
  }
}

/// The live hinge angle, driven straight from the stream.
///
/// Deliberately a `StreamBuilder` rather than a `DuoMediaQuery` dependency:
/// the raw angle updates continuously, and only this widget should rebuild
/// with it.
class _AngleCard extends StatelessWidget {
  const _AngleCard();

  @override
  Widget build(BuildContext context) {
    // Live, unthrottled: DuoMediaQuery.angleOf applies a 0.5 degree threshold,
    // which is right for layout but hides small movements from the reader.
    return StreamBuilder<double>(
      stream: Foldable.hingeAngleStream,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
        final double? angle =
            snapshot.data ?? DuoMediaQuery.angleOf(context);
        return _buildCard(context, angle);
      },
    );
  }

  Widget _buildCard(BuildContext context, double? angle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Hinge angle',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(
                  angle == null ? '--' : '${angle.toStringAsFixed(1)}°',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Transform.rotate(
                    angle: ((angle ?? 180) - 180) * 3.1415926535 / 180 / 2,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '0° closed, 180° flat',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout that adapts to the fold.
class _FoldAwareCard extends StatelessWidget {
  const _FoldAwareCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'FoldAwareBuilder',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: FoldAwareBuilder(
                builder:
                    (
                      BuildContext context,
                      BoxConstraints constraints,
                      FoldInfo fold,
                    ) {
                      if (!fold.spansDivision) {
                        return _Pane(
                          label: fold.isRegularWidth
                              ? 'Single pane, regular width'
                              : 'Single pane, compact width',
                          detail: 'no fold crosses this area',
                        );
                      }
                      return Row(
                        children: const <Widget>[
                          Expanded(
                            child: _Pane(label: 'Leading', detail: 'left of fold'),
                          ),
                          SizedBox(width: 24),
                          Expanded(
                            child: _Pane(
                              label: 'Trailing',
                              detail: 'right of fold',
                            ),
                          ),
                        ],
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Shows what bridging to `MediaQuery.displayFeatures` actually does.
class _BridgeCard extends StatelessWidget {
  const _BridgeCard({required this.bridgeMode, required this.onChanged});

  final DisplayFeatureBridgeMode bridgeMode;
  final ValueChanged<DisplayFeatureBridgeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'MediaQuery bridge',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'With "full" and a partially open device, Flutter confines every '
              'dialog, sheet and picker to one side of the fold. Open the '
              'dialog in each mode to see it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<DisplayFeatureBridgeMode>(
              segments: const <ButtonSegment<DisplayFeatureBridgeMode>>[
                ButtonSegment<DisplayFeatureBridgeMode>(
                  value: DisplayFeatureBridgeMode.none,
                  label: Text('none'),
                ),
                ButtonSegment<DisplayFeatureBridgeMode>(
                  value: DisplayFeatureBridgeMode.cutoutsOnly,
                  label: Text('cutouts'),
                ),
                ButtonSegment<DisplayFeatureBridgeMode>(
                  value: DisplayFeatureBridgeMode.full,
                  label: Text('full'),
                ),
              ],
              selected: <DisplayFeatureBridgeMode>{bridgeMode},
              onSelectionChanged: (Set<DisplayFeatureBridgeMode> s) =>
                  onChanged(s.first),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('Dialog'),
                  content: Text(
                    'Width: '
                    '${MediaQuery.sizeOf(context).width.toStringAsFixed(0)}pt '
                    'available',
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open a dialog'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drives the provider from synthetic data.
class _SimulatorCard extends StatelessWidget {
  const _SimulatorCard({
    required this.simulate,
    required this.status,
    required this.angle,
    required this.onSimulateChanged,
    required this.onStatusChanged,
    required this.onAngleChanged,
  });

  final bool simulate;
  final HingeStatus status;
  final double angle;
  final ValueChanged<bool> onSimulateChanged;
  final ValueChanged<HingeStatus> onStatusChanged;
  final ValueChanged<double> onAngleChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Simulator',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Switch(value: simulate, onChanged: onSimulateChanged),
              ],
            ),
            Text(
              'No foldable simulator profile exists yet, so this feeds '
              'synthetic readings to exercise the layout.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<HingeStatus>(
              segments: const <ButtonSegment<HingeStatus>>[
                ButtonSegment<HingeStatus>(
                  value: HingeStatus.closed,
                  label: Text('closed'),
                ),
                ButtonSegment<HingeStatus>(
                  value: HingeStatus.partiallyOpen,
                  label: Text('partial'),
                ),
                ButtonSegment<HingeStatus>(
                  value: HingeStatus.fullyOpen,
                  label: Text('full'),
                ),
              ],
              selected: <HingeStatus>{
                status == HingeStatus.unknown ? HingeStatus.fullyOpen : status,
              },
              onSelectionChanged: simulate
                  ? (Set<HingeStatus> s) => onStatusChanged(s.first)
                  : null,
            ),
            Slider(
              value: angle.clamp(0, 180),
              max: 180,
              divisions: 180,
              label: '${angle.toStringAsFixed(0)}°',
              onChanged: simulate ? onAngleChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Dumps the Objective-C runtime shape of the hinge APIs.
///
/// Apple's reference documentation for `UIHingeInteraction` is not published,
/// so this is how the real selectors get confirmed on real hardware.
class _DumpPage extends StatelessWidget {
  const _DumpPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native API dump')),
      body: FutureBuilder<Map<String, Object?>>(
        future: Foldable.debugDumpNativeApi(),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<Map<String, Object?>> snapshot,
            ) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(snapshot.data),
                  style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
                ),
              );
            },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 130, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
