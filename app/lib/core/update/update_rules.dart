/// A version of Grove: `1.2.3`. A tag on GitHub has a `v` in front
/// (`v1.2.3`); `pubspec.yaml` has the build number after a `+` (`1.2.3+4`).
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(\+\S*)?$');

  /// Null for a name that is not a plain version, such as a test build
  /// (`1.2.3-beta`).
  static AppVersion? parse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    return AppVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// The systems Grove is made for. Each has its own file in a release.
enum UpdatePlatform {
  macos('grove-macos.zip'),
  windows('grove-windows.zip'),
  android('grove-android.apk'),

  /// An iPhone cannot install a file from GitHub.
  ios(null),
  other(null);

  const UpdatePlatform(this.fileName);

  /// The name of the file of this system in a release, from
  /// `scripts/github_release.sh`.
  final String? fileName;
}

/// One release of Grove on GitHub.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.pageUrl,
    this.notes = '',
    this.files = const {},
  });

  final AppVersion version;

  /// The page of the release, with its words.
  final String pageUrl;

  /// The words of the release.
  final String notes;

  /// The name of each file, and the link that downloads it.
  final Map<String, String> files;

  /// The answer of `GET /repos/{repo}/releases/latest`. Null for a draft, a
  /// test build, a tag that is not a version, or a page that is not on the
  /// GitHub of Grove. A file with a link outside it is left out.
  static ReleaseInfo? fromGitHub(Map<String, Object?> json) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'], page = json['html_url'];
    if (tag is! String || page is! String) return null;
    final version = AppVersion.parse(tag);
    if (version == null || !UpdateRules.isOurs(page)) return null;
    final body = json['body'];
    final assets = json['assets'];
    return ReleaseInfo(
      version: version,
      pageUrl: page,
      notes: body is String ? body : '',
      files: {
        if (assets is List)
          for (final a in assets)
            if (a is Map &&
                a['name'] is String &&
                a['browser_download_url'] is String &&
                UpdateRules.isOurs(a['browser_download_url'] as String))
              a['name'] as String: a['browser_download_url'] as String,
      },
    );
  }

  /// The link of the file of [platform], or null when this release has none.
  String? downloadFor(UpdatePlatform platform) {
    final name = platform.fileName;
    return name == null ? null : files[name];
  }
}

/// Where Grove looks for a newer version. The app asks GitHub
/// (`services/update_check.dart`); a test gives a fake.
abstract interface class ReleaseSource {
  /// The newest release, or null when there is none. Throws when the
  /// question does not get an answer.
  Future<ReleaseInfo?> latest();
}

abstract final class UpdateRules {
  /// The repository on GitHub that gives Grove out.
  static const repo = 'AndreiOprescu/Grove';

  /// The address of the newest release in the API of GitHub.
  static final latestUrl = Uri.parse(
    'https://api.github.com/repos/$repo/releases/latest',
  );

  /// True for a link on the GitHub of Grove. Grove opens no other link
  /// from an answer.
  static bool isOurs(String url) => url.startsWith('https://github.com/$repo/');

  /// True when [release] is newer than [current] and than the version the
  /// person chose to skip.
  static bool isNew(
    ReleaseInfo release, {
    required AppVersion current,
    AppVersion? skipped,
  }) =>
      release.version > current &&
      (skipped == null || release.version > skipped);
}
