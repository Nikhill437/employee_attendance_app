import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/supervisor_login_viewmodel.dart';

/// Supervisor login, authenticated against the backend.
class LoginScreen extends StatefulWidget {
  /// Overridable so tests can inject a fake (avoids the real
  /// SupervisorAuthRepository/LookupRepository, which need network access
  /// the test environment doesn't provide).
  final SupervisorLoginViewModel? viewModel;

  const LoginScreen({super.key, this.viewModel});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final SupervisorLoginViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? SupervisorLoginViewModel();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_viewModel.errorMessage!)),
      );
      _viewModel.consumeError();
      return;
    }

    Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
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
              if (!isKeyboardVisible) ...[
                const SizedBox(height: 23),
                const AppFooterImage(),
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
              showTagline: false,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Username or Email',
              hint: 'Enter your username',
              icon: Icons.person_outline,
              controller: _usernameController,
              validator: _validateRequired,
            ),
            const SizedBox(height: 18),
            AppTextField(
              label: 'Password',
              hint: 'Enter your password',
              icon: Icons.password,
              controller: _passwordController,
              obscureText: true,
              validator: _validateRequired,
              // No onSubmitted → _login(): login only ever runs from the
              // explicit tap on the Login button below, not from pressing
              // the keyboard's done/return action.
            ),
            const SizedBox(height: 28),
            AppPrimaryButton(label: 'Login', onPressed: _login),
          ],
        ),
      ),
    );
  }

  String? _validateRequired(String? value) =>
      (value == null || value.isEmpty) ? 'Required' : null;
}
