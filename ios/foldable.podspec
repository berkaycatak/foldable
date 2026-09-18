#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint foldable.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'foldable'
  s.version          = '0.3.0'
  s.summary          = 'Hinge angle and fold posture for the foldable iPhone.'
  s.description      = <<-DESC
Exposes the iPhone Duo hinge angle, fold posture and reserved fold/camera
regions to Flutter. Compiles against iOS 13 and older SDKs; on any device
without a hinge it reports isFoldable: false and an empty stream.
                       DESC
  s.homepage         = 'https://github.com/berkaycatak/foldable'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Berkay Catak' => 'berkaypng@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'foldable/Sources/foldable/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # With Xcode 27.1+, add '-D FOLDABLE_NATIVE_API' here to compile
    # NativeSources.swift against the real iOS 27.1 hinge types. Without it
    # the hinge is read through the Objective-C runtime, which is what keeps
    # this podspec buildable on older toolchains at an iOS 13 deployment
    # target.
    'OTHER_SWIFT_FLAGS' => '$(inherited)',
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'foldable_privacy' => ['foldable/Sources/foldable/PrivacyInfo.xcprivacy']}
end
