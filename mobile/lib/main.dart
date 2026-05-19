import 'package:flutter/material.dart';
import 'core/theme/theme.dart';
import 'core/session/user_session.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Membaca session tersimpan secara asinkron sebelum widget dirender
  final bool isLoggedIn = await UserSession.loadSession();
  
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clockit',
      theme: AppTheme.lightTheme,
      home: isLoggedIn ? const EmployeeHomeScreen() : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
