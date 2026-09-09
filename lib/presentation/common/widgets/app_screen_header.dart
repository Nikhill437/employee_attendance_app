import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Green banner with rounded bottom corners that tops the light screens.
///
/// Carries a title, an optional subtitle, an optional back button and any
/// trailing [actions] (see [CircleHeaderAction]).
class AppScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;

  /// Replaces the title area entirely — used for an inline search field.
  final Widget? titleOverride;

  final List<Widget> actions;

  const AppScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.titleOverride,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      decoration: const BoxDecoration(
        color: AppColors.gradientTop,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showBack) ...[
              CircleHeaderAction(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(child: titleOverride ?? _buildTitle()),
            for (final action in actions) ...[
              const SizedBox(width: 10),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ],
    );
  }
}

/// Round translucent icon button used inside [AppScreenHeader].
class CircleHeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const CircleHeaderAction({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.16),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: Colors.white),
        tooltip: tooltip,
      ),
    );
  }
}
