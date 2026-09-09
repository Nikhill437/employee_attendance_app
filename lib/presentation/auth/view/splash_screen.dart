import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../common/widgets/common_widgets.dart';

/// Landing screen: brand mark over the palm backdrop, with the two entry
/// points into the app pinned to the bottom.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackgroundScreen(
        child: Stack(
          children: [
            // Decorative layers go first so they sit *behind* the controls,
            // and ignore pointers so they can never swallow a tap.
            const Positioned.fill(
              child: IgnorePointer(
                child: Image(
                  image: AssetImage('assets/bg/bg.png'),
                  fit: BoxFit.fitHeight,
                  opacity: AlwaysStoppedAnimation(0.2),
                ),
              ),
            ),
            const Positioned(
              left: 30,
              right: 30,
              top: 5,
              bottom: 80,
              child: IgnorePointer(
                child: Image(
                  image: AssetImage('assets/logo/logo.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 15,
              child: _buildActions(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          _EntryPointButton(
            label: 'Mark Attendance',
            filled: true,
            onTap: () => Navigator.pushNamed(context, AppRoutes.markAttendance),
          ),
          const SizedBox(height: 20),
          _EntryPointButton(
            supervisor: true,
            label: 'Supervisor Login',
            filled: false,
            onTap: () => Navigator.pushNamed(context, AppRoutes.login),
          ),
          AppLinkText(
            label: 'Forget Password?',
            fontSize: 16,
            onTap: () => _onForgotPassword(context),
          ),
          const AppVersionLabel(color: Colors.white),
        ],
      ),
    );
  }

  /// There is no password-reset flow yet, so this points the user at the one
  /// route that does work today rather than silently doing nothing.
  void _onForgotPassword(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contact your supervisor to reset your password'),
      ),
    );
  }
}

/// One of the two landing actions: white when [filled], outlined otherwise.
class _EntryPointButton extends StatelessWidget {
  final bool? supervisor;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _EntryPointButton({
    this.supervisor,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.transparent,
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(
            supervisor == true ? Icons.shield_outlined : Icons.check_circle,
            color: supervisor == true ? Colors.white : Colors.green,
          ),
          title: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: filled ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
