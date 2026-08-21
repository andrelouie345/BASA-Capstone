import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/validators/auth_validators.dart';
import '../../../shared/widgets/basa_feature_item.dart';
import '../../../shared/widgets/basa_logo.dart';
import '../../../shared/widgets/basa_password_field.dart';
import '../../../shared/widgets/basa_text_field.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../widgets/role_selector.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  UserRole _selectedRole = UserRole.teacher;
  bool _isLoading = false;

  final AuthService _authService = MockAuthService();

  String? _validateUsername(String? value) => AuthValidators.validateUsername(value);

  String? _validatePassword(String? value) => AuthValidators.validatePassword(value);

  Future<void> _handleSignIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isLoading = true);

    final success = await _authService.login(
      username: _usernameController.text,
      password: _passwordController.text,
      role: _selectedRole,
    );

    if (!mounted) return;

    if (!success) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to sign in with the provided credentials.'),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacementNamed(
      AppRoutes.dashboard,
      arguments: {
        'role': _selectedRole.label,
      },
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (isDesktop) {
              return Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: _buildLeftPanel(),
                  ),
                  Expanded(
                    flex: 6,
                    child: _buildRightPanel(constraints),
                  ),
                ],
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      _buildMobileBranding(),
                      const SizedBox(height: 18),
                      _buildRightPanel(constraints, isMobile: true),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(42, 42, 42, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B234B), Color(0xFF123B73)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 80,
            right: 40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(180),
              ),
            ),
          ),
          Positioned(
            bottom: 70,
            left: 20,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BasaLogo(size: 38),
                  const SizedBox(width: 12),
                  const Text(
                    'BASA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'READING DEV. SYSTEM',
                style: TextStyle(
                  color: Color(0xFFB9CEEB),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Empowering Every\nFilipino Reader.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'An integrated reading assessment and learning recovery system supporting CRLA, Phil-IRI, and ARAL Program implementation in DepEd schools.',
                style: TextStyle(
                  color: Color(0xFFDAE7FF),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              ...const [
                BasaFeatureItem(
                  icon: Icons.description_outlined,
                  title: 'Centralized Learner Management',
                  description: 'Organize and manage all reading records and profiles',
                ),
                SizedBox(height: 18),
                BasaFeatureItem(
                  icon: Icons.gps_fixed_rounded,
                  title: 'Automated Assessment Scoring',
                  description: 'CRLA, Phil-IRI, and GST with instant classification',
                ),
                SizedBox(height: 18),
                BasaFeatureItem(
                  icon: Icons.calendar_month_rounded,
                  title: 'ARAL Program Management',
                  description: 'Identification, planning, scheduling and monitoring',
                ),
                SizedBox(height: 18),
                BasaFeatureItem(
                  icon: Icons.bar_chart_rounded,
                  title: 'Analytics & Visualization',
                  description: 'Track progress, measure gains, evaluate strategies',
                ),
              ],
              const Spacer(),
              const Text(
                AppConstants.leftFooterLabel,
                style: TextStyle(
                  color: Color(0xFF9CB1D2),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(BoxConstraints constraints, {bool isMobile = false}) {
    return Container(
      color: const Color(0xFFEFF5FC),
      child: Center(
        child: Container(
          width: isMobile ? constraints.maxWidth : 540,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 18 : 28,
            vertical: isMobile ? 20 : 24,
          ),
          margin: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0x1A0B234B),
                offset: const Offset(0, 16),
                blurRadius: 30,
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Sign in to BASA',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF122C5B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use your DepEd credentials to access the system.',
                  style: TextStyle(
                    color: Color(0xFF7D91B2),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 22),
                RoleSelector(
                  selectedRole: _selectedRole,
                  onChanged: (role) => setState(() => _selectedRole = role),
                ),
                const SizedBox(height: 22),
                BasaTextField(
                  label: 'DEPED USERNAME / EMAIL',
                  controller: _usernameController,
                  hintText: 'firstname.lastname@deped.gov.ph',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  validator: _validateUsername,
                  prefixIcon: Icons.email_outlined,
                ),
                const SizedBox(height: 18),
                BasaPasswordField(
                  label: 'PASSWORD',
                  controller: _passwordController,
                  validator: _validatePassword,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignIn,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
                      child: const Text('Forgot password?'),
                    ),
                    TextButton(
                      onPressed: _showSupportDialog,
                      child: const Text('Contact IT Support'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Center(
                  child: Column(
                    children: [
                      Text(
                        AppConstants.footerSchoolLabel,
                        style: TextStyle(
                          color: Color(0xFF7D91B2),
                          fontSize: 11,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        AppConstants.footerVersionLabel,
                        style: TextStyle(
                          color: Color(0xFF7D91B2),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBranding() {
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B234B), Color(0xFF123B73)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                BasaLogo(size: 34),
                SizedBox(width: 10),
                Text(
                  'BASA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'READING DEV. SYSTEM',
              style: TextStyle(
                color: Color(0xFFB9CEEB),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.06,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Contact IT Support'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('For technical support, contact the school ICT Team.'),
              SizedBox(height: 12),
              Text('Email: it-support@deped.gov.ph'),
              Text('Phone: (02) 1234-5678'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
