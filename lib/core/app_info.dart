/// The version shown under Me > About. Keep in step with `version:` in pubspec.yaml
/// (a test checks it). A release build may pass its own with --build-name and --build-number.
const appVersion = String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '1.0.0');
const appBuild = String.fromEnvironment('FLUTTER_BUILD_NUMBER', defaultValue: '1');

String get appVersionLabel => 'Version $appVersion (build $appBuild)';
