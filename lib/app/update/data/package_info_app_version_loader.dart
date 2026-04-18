import 'package:package_info_plus/package_info_plus.dart';

class PackageInfoAppVersionLoader {
  Future<String> loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version.trim();
  }
}
