import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // Package QR Scanner populer Flutter
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile/core/session/user_session.dart';
import 'package:google_fonts/google_fonts.dart';

class ScanAttendanceScreen extends StatefulWidget {
  final double? cachedLatitude;
  final double? cachedLongitude;

  const ScanAttendanceScreen({
    super.key,
    this.cachedLatitude,
    this.cachedLongitude,
  });

  @override
  State<ScanAttendanceScreen> createState() => _ScanAttendanceScreenState();
}

class _ScanAttendanceScreenState extends State<ScanAttendanceScreen> {
  Position? _currentPosition;
  bool _isLocating = true;
  String? _locationError;
  bool _isProcessingAbsence = false;
  bool _isWfh = false;

  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates, // Hindari double-scanning
  );

  @override
  void initState() {
    super.initState();
    if (widget.cachedLatitude != null && widget.cachedLongitude != null) {
      _currentPosition = Position(
        latitude: widget.cachedLatitude!,
        longitude: widget.cachedLongitude!,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
      _isLocating = false;
    } else {
      _startPermissionAndGPSFlow();
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  /// Memulai inisialisasi Kamera & GPS secara bersamaan (Concurrently)
  Future<void> _startPermissionAndGPSFlow() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      // 1. Cek & Minta Izin Lokasi
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationServiceDialog();
        throw 'GPS Anda mati. Harap nyalakan GPS ponsel.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Izin lokasi ditolak.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showAppSettingsDialog();
        throw 'Izin lokasi ditolak permanen. Buka Pengaturan HP Anda.';
      }

      // 2. Ambil Posisi GPS Akurasi Tinggi (High Accuracy)
      // Menggunakan Geolocator.getCurrentPosition secara asinkronus
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _currentPosition = position;
        _isLocating = false;
      });
      debugPrint('📍 GPS Koordinat Terkunci: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      setState(() {
        _locationError = e.toString();
        _isLocating = false;
      });
      debugPrint('❌ Gagal mengunci GPS: $e');
    }
  }

  /// Dipanggil otomatis saat kamera berhasil membaca QR Code
  Future<void> _onQRCodeDetected(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? qrToken = barcodes.first.rawValue;
    if (qrToken == null || qrToken.isEmpty) return;

    // Jika GPS belum terkuci, jangan izinkan absen
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Menunggu koordinat GPS stabil. Harap tunggu beberapa detik.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    if (_isProcessingAbsence) return; // Mencegah klik ganda

    setState(() {
      _isProcessingAbsence = true;
    });

    // Stop scanner sejenak saat memproses absensi
    await _scannerController.stop();

    // 3. Payload Gabungan QR Token + GPS Koordinat Aktual
    final Map<String, dynamic> attendancePayload = {
      'qr_token': qrToken,
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      // 'device_id' diambil dari storage login
    };

    debugPrint('📤 Mengirim Payload Presensi: $attendancePayload');
    
    // Tampilkan Animasi Keberhasilan/Kegagalan dengan Dialog Premium
    _showProcessDialog(attendancePayload);
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 24,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: Container(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFCA5A5),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.location_off_rounded,
                      color: Color(0xFFEF4444),
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Aktifkan GPS Anda',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Layanan lokasi (GPS) dinonaktifkan.\n\nHarap aktifkan GPS agar sistem dapat mengunci posisi presensi Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF4B5563), height: 1.5),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('BATAL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Geolocator.openLocationSettings();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('AKTIFKAN', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAppSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 24,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: Container(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFCA5A5),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.security_rounded,
                      color: Color(0xFFEF4444),
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Izin GPS Diblokir',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Akses GPS untuk aplikasi ini diblokir secara permanen.\n\nHarap aktifkan izin lokasi di menu Pengaturan Aplikasi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF4B5563), height: 1.5),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('BATAL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Geolocator.openAppSettings();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('PENGATURAN', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String> _getSilentDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'ios_fallback_device';
      }
      return 'unknown_platform_device';
    } catch (e) {
      return 'fallback_device_id';
    }
  }

  void _showResultDialog({required bool success, required String title, required String message, String? status}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 24,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: Container(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Beautiful Icon Badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: success ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: success ? const Color(0xFFA7F3D0) : const Color(0xFFFCA5A5),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      success ? Icons.check_circle_rounded : Icons.error_rounded,
                      color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      size: 48,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Title
                Text(
                  success ? 'Presensi Berhasil' : 'Presensi Gagal',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Message Body
                if (success)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow('Status', status ?? 'Tepat Waktu', isStatus: true),
                        const Divider(height: 20, color: Color(0xFFF3F4F6)),
                        _buildInfoRow('Akurasi GPS', '${_currentPosition?.accuracy.toStringAsFixed(1) ?? "0"} m'),
                        const Divider(height: 20, color: Color(0xFFF3F4F6)),
                        Text(
                          message.contains('Pesan: ') 
                              ? message.split('Pesan: ').last 
                              : message,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF4B5563),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFEE2E2)),
                    ),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF991B1B),
                        height: 1.6,
                      ),
                    ),
                  ),
                const SizedBox(height: 28),

                // 4. Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Tutup dialog
                      if (success) {
                        Navigator.pop(context, true); // Tutup ScanScreen dan kirim value true
                      } else {
                        if (mounted) {
                          setState(() {
                            _isProcessingAbsence = false;
                          });
                          _scannerController.start(); // Nyalakan kembali kamera
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF111827),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'TUTUP',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF9CA3AF),
            letterSpacing: 0.5,
          ),
        ),
        if (isStatus)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF065F46),
              ),
            ),
          )
        else
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF374151),
            ),
          ),
      ],
    );
  }

  void _showProcessDialog(Map<String, dynamic> payload) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF121212)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Memverifikasi Absen...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sistem sedang melakukan otentikasi tanda tangan QR & batas wilayah Geofence.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      },
    );

    // Kirim request asli ke backend FastAPI
    _submitAttendance(payload);
  }

  Future<void> _submitAttendance(Map<String, dynamic> payload) async {
    try {
      final String deviceId = await _getSilentDeviceId();
      
      final Map<String, dynamic> requestBody = {
        'qr_token': payload['qr_token'],
        'latitude': payload['latitude'],
        'longitude': payload['longitude'],
        'device_id': deviceId,
        'user_id': UserSession.userId, 
        'is_wfh': _isWfh,
      };

      final response = await http.post(
        Uri.parse('http://10.41.159.137:8000/api/v1/attendance/scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (!mounted) return;
      Navigator.pop(context); // Tutup loading dialog

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final String recordedStatus = responseData['status'] ?? 'Tepat Waktu';
        _showResultDialog(
          success: true,
          title: '✅ Absen Masuk Berhasil',
          status: recordedStatus,
          message: 'Status: $recordedStatus\n'
              'Lokasi: ${_isWfh ? "Kerja dari Rumah (WFH)" : "Kantor Pusat"}\n'
              'Akurasi GPS: ${_currentPosition?.accuracy.toStringAsFixed(1)} meter\n'
              'Pesan: ${responseData['message']}',
        );
      } else {
        final responseData = jsonDecode(response.body);
        final String errorMessage = responseData['detail'] ?? 'Gagal memverifikasi presensi.';
        _showResultDialog(
          success: false,
          title: '❌ Absen Gagal',
          message: errorMessage,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Tutup loading dialog
      _showResultDialog(
        success: false,
        title: '⚠️ Koneksi Gagal',
        message: 'Gagal terhubung ke server absensi: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('PINDAI QR PRESENSI', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // 1. Kamera Viewfinder (Mobile Scanner) atau WFH Background
          if (!_isWfh)
            MobileScanner(
              controller: _scannerController,
              onDetect: _onQRCodeDetected,
            )
          else
            Container(color: const Color(0xFF111827)), // Background solid untuk WFH Mode

          // WFH Toggle Overlay
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isWfh = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isWfh ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            '📍 KANTOR (WFO)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: !_isWfh ? Colors.black : Colors.white70,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isWfh = true;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isWfh ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            '🏠 RUMAH (WFH)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _isWfh ? Colors.black : Colors.white70,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Custom Laser Scanner Overlay UI (Visual Frame) atau WFH Check-in Button
          if (!_isWfh)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    // Animasi Laser Line
                    AnimatedContainer(
                      duration: const Duration(seconds: 2),
                      curve: Curves.easeInOut,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 3,
                        width: 230,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(color: Colors.white.withOpacity(0.8), blurRadius: 10, spreadRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 15, spreadRadius: 2),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(100),
                            onTap: _isProcessingAbsence
                                ? null
                                : () {
                                    setState(() {
                                      _isProcessingAbsence = true;
                                    });
                                    _submitAttendance({
                                      'qr_token': 'wfh_bypass',
                                      'latitude': _currentPosition?.latitude ?? 0.0,
                                      'longitude': _currentPosition?.longitude ?? 0.0,
                                    });
                                  },
                            child: const Center(
                              child: Icon(
                                Icons.home_rounded,
                                color: Colors.black,
                                size: 56,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'KLAIM KEHADIRAN WFH',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sentuh tombol Rumah untuk presensi WFH',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // 3. Status Bar GPS Melayang (Real-time GPS Tracking Indicator)
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isLocating ? Icons.gps_fixed : (_locationError != null ? Icons.gps_off : Icons.gps_fixed),
                        color: _isLocating ? Colors.orange : (_locationError != null ? Colors.red : Colors.green),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isLocating 
                                ? 'Mencari Sinyal GPS...' 
                                : (_locationError != null ? 'GPS Error' : 'GPS Terkunci (Presisi)'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A1A1A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isLocating 
                                ? 'Mengunci sinyal satelit dengan akurasi tinggi...' 
                                : (_locationError ?? 'Lat: ${_currentPosition?.latitude.toStringAsFixed(6)}, Lng: ${_currentPosition?.longitude.toStringAsFixed(6)}'),
                              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      if (_isLocating)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange)),
                        )
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
