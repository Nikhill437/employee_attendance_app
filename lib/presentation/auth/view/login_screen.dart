import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/routes/app_routes.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/supervisor_login_viewmodel.dart';

/// Supervisor login, authenticated against the backend.
class LoginScreen extends StatefulWidget {
  final SupervisorLoginViewModel? viewModel;

  const LoginScreen({super.key, this.viewModel});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const int _usernameMaxLength = 20;

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final SupervisorLoginViewModel _viewModel;
  bool _obscurePassword = true;

  /// `pubspec.yaml`'s `version:` (the part before the `+build` suffix) —
  /// null until [PackageInfo.fromPlatform] resolves, so nothing shows
  /// until then rather than a wrong placeholder.
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? SupervisorLoginViewModel();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = info.version);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await _viewModel.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_viewModel.errorMessage!)));
      _viewModel.consumeError();
      return;
    }

    // Shown through the app-level messenger, so it stays visible on the
    // dashboard once this screen's route is replaced below.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Login Successfully')));

    // Clears the whole stack (splash included), not just this screen —
    // pushReplacementNamed alone would leave splash sitting right below
    // Dashboard, so back/swipe-back could still escape to it. Dashboard
    // becomes the sole route until Settings > Logout clears it the same
    // way in the other direction.
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.dashboard,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hidden while the keyboard is up — otherwise the Column just
    // compresses to fit both the form and the footer image into the
    // shrunken space, squeezing the form and inviting overflow instead of
    // giving the form (and the keyboard) the room they need.
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackgroundScreen(
        child: SafeArea(
          child: Column(
            children: [
              // Expanded so the form scrolls within the space left over when
              // the keyboard opens, instead of overflowing.
              Expanded(child: _buildForm()),
              if (!isKeyboardVisible && _appVersion != null) ...[
                const SizedBox(height: 23),
                Text(
                  'v$_appVersion',
                  style: const TextStyle(letterSpacing: 1.2,
              color: Colors.white70,),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.08),
            const BrandHeader(
              logoWidth: 320,
              logoHeight: 220,
              showTagline: true,
            ),
            const SizedBox(height: 60),
            AppTextField(
              label: 'Username or Email',
              hint: 'Enter your username',
              icon: Icons.person_outline,
              controller: _usernameController,
              maxLength: _usernameMaxLength,
              validator: _validateUsername,
            ),
            const SizedBox(height: 18),
            AppTextField(
              label: 'Password',
              hint: 'Enter your password',
              icon: Icons.password,
              controller: _passwordController,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: _validateRequired,
            ),
            const SizedBox(height: 28),
            AppPrimaryButton(label: 'Login', onPressed: _login),
            SizedBox(height: 4),
            TextButton(onPressed: ()=> Navigator.pop(context), child: Text(
                    'Back to Home',
                    style: TextStyle(fontSize: 16, color: Colors.white),)),
          ],
        ),
      ),
    );
  }

  String? _validateRequired(String? value) =>
      (value == null || value.isEmpty) ? 'Required' : null;

  String? _validateUsername(String? value) {
    final required = _validateRequired(value);
    if (required != null) return required;
    if (value!.length > _usernameMaxLength) {
      return 'Username must be $_usernameMaxLength characters or fewer';
    }
    return null;
  }
}
