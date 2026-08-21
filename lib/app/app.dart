import 'package:flutter/material.dart';

import '../features/authentication/screens/login_screen.dart';
import '../features/authentication/screens/forgot_password_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/learners/screens/learner_profiles_screen.dart';
import 'routes.dart';
import 'theme.dart';

class BasaApp extends StatelessWidget {
  const BasaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BASA - Reading Development System',
      debugShowCheckedModeBanner: false,
      theme: BasaTheme.lightTheme,
      initialRoute: AppRoutes.login,
      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.forgotPassword: (_) => const ForgotPasswordScreen(),
        AppRoutes.dashboard: (_) => const DashboardScreen(initialRoute: AppRoutes.dashboard),
        AppRoutes.learners: (_) => const DashboardScreen(initialRoute: AppRoutes.learners),
        AppRoutes.assessments: (_) => const DashboardScreen(initialRoute: AppRoutes.assessments),
      },
    );
  }
}
