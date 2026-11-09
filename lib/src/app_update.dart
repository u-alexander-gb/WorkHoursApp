import 'app_version.dart';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.releaseUrl,
    this.androidUrl,
    this.windowsUrl,
  });

  final String version;
  final String releaseUrl;
  final String? androidUrl;
  final String? windowsUrl;
}

AppUpdate? parseUpdateManifest(Object decoded, String installedVersion) {
  if (decoded is! Map) {
    throw const FormatException('Update manifest is not an object');
  }
  String requiredString(String key) {
    final value = decoded[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Update manifest field "$key" is invalid');
    }
    return value;
  }

  final version = requiredString('version');
  if (!isNewerAppVersion(version, installedVersion)) return null;
  final releaseUrl = requiredString('releaseUrl');
  String? optionalString(String key) {
    final value = decoded[key];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  return AppUpdate(
    version: version,
    releaseUrl: releaseUrl,
    androidUrl: optionalString('androidUrl'),
    windowsUrl: optionalString('windowsUrl'),
  );
}
