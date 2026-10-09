import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The build number shown at the foot of the green screens.
class AppVersionLabel extends StatefulWidget {
  final Color color;

  const AppVersionLabel({super.key, this.color = Colors.white38});

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  /// Kept in step with the `version:` field in pubspec.yaml.
 String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = info.version);
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('v$_appVersion',
                      style: const TextStyle(letterSpacing: 1.2,
                  color: Colors.white70,),
                    ),
                    const SizedBox(height: 10),
      ],
    );           
  }
}
