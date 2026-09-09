import 'package:flutter/material.dart';

/// The build number shown at the foot of the green screens.
class AppVersionLabel extends StatelessWidget {
  /// Kept in step with the `version:` field in pubspec.yaml.
  static const String version = 'v1.0.0';

  final Color color;

  const AppVersionLabel({super.key, this.color = Colors.white38});

  @override
  Widget build(BuildContext context) {
    return Text(version, style: TextStyle(fontSize: 12, color: color));
  }
}
