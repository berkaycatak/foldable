/// Foldable iPhone support for Flutter.
///
/// Exposes the hinge angle, fold posture and fold/camera display regions of the
/// iPhone Duo, Apple's first foldable iPhone, to Flutter apps.
///
/// Flutter does not populate `MediaQuery.displayFeatures` on iOS. `dart:ui`
/// states outright that display features are "populated only on Android", so
/// none of this information reaches a Flutter app on its own. This package
/// bridges it over a platform channel.
///
/// The package is safe to depend on unconditionally: it compiles against
/// iOS 13 and older SDKs, and on any device without a hinge it reports
/// `isFoldable: false` with an empty stream.
///
/// ```dart
/// // Outside the widget tree
/// if (await Foldable.isFoldable) {
///   Foldable.hingeAngleStream.listen((degrees) => print('$degrees°'));
/// }
///
/// // Inside the widget tree
/// FoldableProvider(
///   child: FoldAwareBuilder(
///     builder: (context, constraints, fold) => fold.isPartiallyOpen
///         ? const TwoPaneLayout()
///         : const SinglePaneLayout(),
///   ),
/// )
/// ```
library;

export 'src/bridge/display_feature_bridge.dart';
export 'src/foldable_api.dart';
export 'src/model/foldable_capabilities.dart';
export 'src/model/foldable_data.dart';
export 'src/model/hinge_status.dart';
export 'src/model/reserved_region.dart';
export 'src/platform/foldable_method_channel.dart'
    show kFoldableEventChannel, kFoldableMethodChannel, MethodChannelFoldable;
export 'src/platform/foldable_platform.dart';
export 'src/widgets/duo_media_query.dart';
export 'src/widgets/fold_aware_builder.dart';
export 'src/widgets/foldable_provider.dart';
