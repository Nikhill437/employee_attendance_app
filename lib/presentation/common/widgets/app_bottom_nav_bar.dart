import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// One entry in [AppBottomNavBar].
enum AppSection {
  dashboard(Icons.grid_view_rounded, 'Dashboard'),
  workers(Icons.people_outline, 'Workers'),
  reports(Icons.bar_chart, 'Reports'),
  settings(Icons.settings_outlined, 'Settings');

  const AppSection(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The app's primary navigation bar.
///
/// Purely presentational: it reports the tapped section and lets the hosting
/// screen decide what to do, so it can be dropped onto any screen.
class AppBottomNavBar extends StatelessWidget {
  final AppSection current;
  final ValueChanged<AppSection> onSectionSelected;

  const AppBottomNavBar({
    super.key,
    required this.current,
    required this.onSectionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _colorFor(states),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(size: 24, color: _colorFor(states)),
        ),
      ),
      child: NavigationBar(
        height: 68,
        selectedIndex: current.index,
        onDestinationSelected: (index) =>
            onSectionSelected(AppSection.values[index]),
        destinations: [
          for (final section in AppSection.values)
            NavigationDestination(
              icon: Icon(section.icon),
              label: section.label,
            ),
        ],
      ),
    );
  }

  Color _colorFor(Set<WidgetState> states) =>
      states.contains(WidgetState.selected)
      ? AppColors.deepGreen
      : AppColors.muted;
}
