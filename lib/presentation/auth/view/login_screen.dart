import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/supervisor_login_viewmodel.dart';

/// Supervisor login, checked against the single fixed supervisor account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final SupervisorLoginViewModel _viewModel = SupervisorLoginViewModel();

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackgroundScreen(
        child: SafeArea(
          child: Column(
            children: [
              // Expanded so the form scrolls within the space left over when
              // the keyboard opens, instead of overflowing.
              Expanded(child: _buildForm()),
              const SizedBox(height: 23),
              const AppFooterImage(),
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
              onSubmitted: (_) => _login(),
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
