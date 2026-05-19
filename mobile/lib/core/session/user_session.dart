import 'package:shared_preferences/shared_preferences.dart';

class UserSession {
  static int userId = 1;
  static String fullName = 'Budi Santoso';
  static String token = '';

  /// Menyimpan data session ke SharedPreferences setelah login sukses
  static Future<void> saveSession({
    required int id,
    required String name,
    required String userToken,
  }) async {
    userId = id;
    fullName = name;
    token = userToken;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userId', id);
    await prefs.setString('fullName', name);
    await prefs.setString('token', userToken);
    await prefs.setBool('isLoggedIn', true);
  }

  /// Membaca data session dari SharedPreferences saat aplikasi dibuka
  static Future<bool> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn) {
      userId = prefs.getInt('userId') ?? 1;
      fullName = prefs.getString('fullName') ?? 'Budi Santoso';
      token = prefs.getString('token') ?? '';
      return true;
    }
    return false;
  }

  /// Menghapus seluruh data session saat melakukan logout
  static Future<void> clearSession() async {
    userId = 1;
    fullName = 'Budi Santoso';
    token = '';

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
