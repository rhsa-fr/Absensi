import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/session/user_session.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Function(String)? onNotificationTapped;

  bool _initialized = false;

  /// Inisialisasi Firebase Cloud Messaging & Saluran Lokal
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 1. Inisialisasi Firebase Core
      await Firebase.initializeApp();

      // 2. Minta Izin Notifikasi Sistem (Android 13+ & iOS)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // Pemicu Dialog Izin Sistem Android 13+ secara paksa
      try {
        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (permissionErr) {
        debugPrint('Gagal memicu dialog izin lokal: $permissionErr');
      }

      debugPrint('Permission status: ${settings.authorizationStatus}');

      // 3. Konfigurasi Saluran Notifikasi Lokal untuk Android (Agar Muncul Heads-Up Banner saat app aktif)
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'clockit_push_channel', // id
        'Clockit Push Notifications', // name
        description: 'Saluran notifikasi real-time untuk status absensi dan cuti karyawan.', // description
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      // Daftarkan saluran ke perangkat Android
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Inisialisasi pengaturan notifikasi lokal
      const AndroidInitializationSettings androidInit = AndroidInitializationSettings('ic_launcher');
      const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
      const InitializationSettings initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notifikasi ditap oleh user: ${response.payload}');
          if (response.payload != null && onNotificationTapped != null) {
            try {
              final data = jsonDecode(response.payload!);
              final page = data['page'];
              if (page != null) {
                onNotificationTapped!(page.toString());
              }
            } catch (e) {
              debugPrint('Gagal parsing payload notifikasi: $e');
            }
          }
        },
      );

      // 4. Tangani Notifikasi saat Aplikasi sedang Terbuka (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Menerima push notification di FOREGROUND: ${message.notification?.title}');
        
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        if (notification != null && android != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: 'ic_launcher',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            payload: jsonEncode(message.data),
          );
        }
      });

      // 5. Tangani Notifikasi saat Aplikasi di Background tapi masih menyala
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Aplikasi dibuka via Push Notification di BACKGROUND: ${message.notification?.title}');
        final page = message.data['page'];
        if (page != null && onNotificationTapped != null) {
          onNotificationTapped!(page.toString());
        }
      });

      // 6. Tangani jika Aplikasi mati total dan dibuka via Tap Notifikasi
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('Aplikasi dinyalakan dari kondisi mati via Tap Notifikasi: ${initialMessage.notification?.title}');
        final page = initialMessage.data['page'];
        if (page != null) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (onNotificationTapped != null) {
              onNotificationTapped!(page.toString());
            }
          });
        }
      }

      _initialized = true;
      debugPrint('🔔 NotificationService berhasil diinisialisasi secara profesional!');
    } catch (e) {
      debugPrint('⚠️ Gagal menginisialisasi NotificationService: $e');
    }
  }

  /// Mendapatkan FCM Token unik perangkat HP ini
  Future<String?> getFcmToken() async {
    if (!_initialized) {
      debugPrint('FCM dipanggil sebelum inisialisasi selesai. Menyiapkan Firebase...');
      await initialize();
    }
    try {
      String? token = await _messaging.getToken();
      debugPrint('FCM TOKEN HP Anda: $token');
      return token;
    } catch (e) {
      debugPrint('Gagal mengambil FCM Token: $e');
      return null;
    }
  }

  /// Mengirimkan FCM Token ke backend FastAPI agar terikat dengan Akun Karyawan
  Future<bool> bindFcmTokenToServer() async {
    final int userId = UserSession.userId;
    if (userId == 0) return false;

    String? token = await getFcmToken();
    if (token == null) return false;

    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.7:8000/api/v1/users/$userId/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fcm_token': token}),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ FCM Token berhasil diikat dengan User ID $userId di database!');
        return true;
      } else {
        debugPrint('❌ Gagal mengikat FCM Token ke server: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Terjadi gangguan jaringan saat mengikat FCM Token: $e');
      return false;
    }
  }
}
