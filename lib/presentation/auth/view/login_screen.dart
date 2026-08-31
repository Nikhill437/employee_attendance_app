import 'package:employee_attendance_app/core/utils/background.dart';
import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  /// There is no password-reset flow yet, so this points the user at the one
  /// route that does work today rather than silently doing nothing.
  void _onForgotPassword(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contact your supervisor to reset your password'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundScreen(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Decorative layers go first so they sit *behind* the controls,
            // and ignore pointers so they can never swallow a tap.
            Positioned.fill(
              child: IgnorePointer(
                child: Image.asset(
                  'assets/bg/bg.png',
                  fit: BoxFit.fitHeight,
                  opacity: const AlwaysStoppedAnimation(0.2),
                ),
              ),
            ),
            Positioned(
              right: 30,
              left: 30,
              bottom: 80,
              top: 5,
              child: IgnorePointer(
                child: Image.asset(
                  'assets/logo/logo.png',
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              right: 0,
              left: 0,
              bottom: 15,
              child: Padding(
                padding: const EdgeInsets.only(left: 14.0, right: 14.0),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.markAttendance,
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: BorderSide(color: Colors.white),
                        ),
                        leading: Icon(Icons.check_circle, color: Colors.green),
                        title: Center(child: Text('Mark Attendance')),
                      ),
                    ),

                    GestureDetector(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.markAttendance,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        width: MediaQuery.of(context).size.width * 0.8,
                        height: 50,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login, color: Colors.green),
                            const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.createAttendance,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2.0),
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        width: MediaQuery.of(context).size.width * 0.8,
                        height: 50,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Create Attendance',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _onForgotPassword(context),
                      child: const Text(
                        'Forget Password?',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),
                    ),
                    Text("v1.0.0", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
