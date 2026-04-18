enum AppUpdateCheckPhase { idle, checking, upToDate, updateAvailable, failed }

class AppSemanticVersion implements Comparable<AppSemanticVersion> {
  const AppSemanticVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  factory AppSemanticVersion.parse(String raw) {
    final normalized = raw.trim().replaceFirst(RegExp(r'^v'), '');
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$',
    ).firstMatch(normalized);
    if (match == null) {
      throw FormatException('Invalid semantic version: $raw');
    }
    return AppSemanticVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppSemanticVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) {
      return majorCompare;
    }
    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) {
      return minorCompare;
    }
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.tag,
    required this.releasePageUrl,
  });

  final String version;
  final String tag;
  final String releasePageUrl;
}
