import 'package:flutter/material.dart';
import 'core/theme/theme.dart';
import 'core/session/user_session.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/home_screen.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Membaca session tersimpan secara asinkron agar UI render secepat kilat!
  final bool isLoggedIn = await UserSession.loadSession();
  
  // Jalankan aplikasi utama INSTAN agar tidak membeku (menghindari Black Screen)
  runApp(MyApp(isLoggedIn: isLoggedIn));

  // Inisialisasi Firebase & Push Notification secara asinkron di latar belakang
  final notificationService = NotificationService();
  notificationService.initialize().then((_) {
    if (isLoggedIn) {
      // Ikat token HP ke server backend absensi jika sudah login
      notificationService.bindFcmTokenToServer();
    }
  });
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
