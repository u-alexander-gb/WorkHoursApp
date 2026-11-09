final _versionPattern = RegExp(
  r'^v?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?(?:\+\d+)?$',
);

List<int>? _versionParts(String value) {
  final match = _versionPattern.firstMatch(value.trim());
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    match.group(4) == null ? 1 << 30 : int.parse(match.group(4)!),
  ];
}

int compareAppVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  if (leftParts == null || rightParts == null) return 0;
  for (var index = 0; index < leftParts.length; index++) {
    if (leftParts[index] != rightParts[index]) {
      return leftParts[index].compareTo(rightParts[index]);
    }
  }
  return 0;
}

bool isNewerAppVersion(String latest, String installed) =>
    compareAppVersions(latest, installed) > 0;
