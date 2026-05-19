import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/session/user_session.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mobile/core/services/notification_service.dart';
import '../config.dart';

enum LoginState { initial, loading, success, error }

class LoginController extends ChangeNotifier {
  LoginState _state = LoginState.initial;
  String _errorMessage = '';

  LoginState get state => _state;
  String get errorMessage => _errorMessage;

  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  // Instance Google Sign In
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: googleSignInClientId,
  );

  /// Mengambil Device ID secara silent di latar belakang
  Future<String> _getSilentDeviceId() async {
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfoPlugin.androidInfo;
        // id mewakili hardware ID unik di Android
        return androidInfo.id;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfoPlugin.iosInfo;
        // identifierForVendor mewakili ID unik vendor di iOS
        return iosInfo.identifierForVendor ?? 'unknown_ios_device';
      }
      return 'unknown_platform_device';
    } catch (e) {
      debugPrint('Gagal mendapatkan Device ID: $e');
      return 'fallback_device_id_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Melakukan login dengan silent auto-binding Device ID
  Future<bool> login({required String email, required String password}) async {
    _state = LoginState.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      // 1. Silent fetching Device ID
      final String deviceId = await _getSilentDeviceId();
      debugPrint('🔒 Device ID Terdeteksi: $deviceId');

      // 2. Payload gabungan (Email, Password, dan Device ID)
      final Map<String, dynamic> payload = {
        'email': email.trim(),
        'password': password,
        'device_id': deviceId,
      };

      // 3. Eksekusi request API ke backend FastAPI
      final response = await http.post(
        Uri.parse(
          'http://192.168.1.7:8000/api/v1/auth/login',
        ), // Ubah IP jika dideploy
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Simpan ke UserSession global dan persistensikan ke SharedPreferences
        await UserSession.saveSession(
          id: data['user_id'] ?? 1,
          name: data['full_name'] ?? 'Budi Santoso',
          userToken: data['access_token'] ?? '',
        );

        // Bind FCM Token to backend server
        NotificationService().bindFcmTokenToServer();

        _state = LoginState.success;
        notifyListeners();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage =
            data['detail'] ?? 'Gagal masuk. Cek email dan password Anda.';
        _state = LoginState.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('Koneksi Error: $e');
      _errorMessage = 'Gagal terhubung ke server. Pastikan backend aktif.';
      _state = LoginState.error;
      notifyListeners();
      return false;
    }
  }

  /// Melakukan login Google SSO dengan auto-registration
  Future<bool> loginWithGoogle() async {
    _state = LoginState.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      // 1. Silent fetching Device ID
      final String deviceId = await _getSilentDeviceId();
      debugPrint('🔒 Device ID Terdeteksi: $deviceId');

      // 2. Lakukan otentikasi Google Sign In nyata
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _state = LoginState.initial;
        _errorMessage = 'Login dibatalkan oleh pengguna.';
        notifyListeners();
        return false;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception("Gagal mendapatkan ID Token dari Google.");
      }

      // 3. Kirim payload Google Token & Device ID ke FastAPI backend
      final response = await http.post(
        Uri.parse('http://192.168.1.7:8000/api/v1/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken, 'device_id': deviceId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Simpan sesi global
        await UserSession.saveSession(
          id: data['user_id'] ?? 1,
          name: data['full_name'] ?? 'Karyawan Google',
          userToken: data['access_token'] ?? '',
        );

        // Bind FCM Token to backend server
        NotificationService().bindFcmTokenToServer();

        _state = LoginState.success;
        notifyListeners();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage =
            data['detail'] ?? 'Otentikasi Google ditolak oleh backend.';
        _state = LoginState.error;
        notifyListeners();
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('Google Sign In Error: ${e.code} ${e.message}');
      _errorMessage = _buildGoogleSignInErrorMessage(e);
      _state = LoginState.error;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
      _errorMessage =
          'Terjadi kesalahan saat otentikasi Google. Coba lagi nanti.';
      _state = LoginState.error;
      notifyListeners();
      return false;
    }
  }

  String _buildGoogleSignInErrorMessage(PlatformException exception) {
    if (exception.code == 'sign_in_failed' &&
        exception.message?.contains('ApiException: 10') == true) {
      return 'Google Sign-In gagal: konfigurasi OAuth Android tidak valid. Periksa package name, SHA-1 fingerprint, dan google-services.json.';
    }
    return exception.message ?? 'Google Sign-In gagal. Silakan coba lagi.';
  }
}
