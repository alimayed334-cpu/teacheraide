import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'login_screen_new.dart';
import '../main_screen.dart';
import 'banned_screen.dart';
import '../../theme/app_theme.dart';
import '../../database/database_helper.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Show loading while checking authentication
        if (authProvider.isLoading) {
          return Scaffold(
            backgroundColor: const Color(0xFF0D0D0D),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school,
                    size: 80,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(
                    color: Color(0xFFFFD700),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'جاري التحميل...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Check if user is authenticated
        if (authProvider.isAuthenticated) {
          if (authProvider.userRole == UserRole.banned) {
            return const BannedScreen();
          }

          // admin / assistant
          return const MainScreen();
        }

        // Show login screen if not authenticated
        return const LoginScreenNew();
      },
    );
  }
}
