import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

import '../../attendance/presentation/scan_attendance_screen.dart';
import '../../leave/presentation/leave_request_screen.dart';
import '../../auth/presentation/login_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/core/session/user_session.dart';

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  int _currentIndex = 0;

  // Data status kehadiran hari ini dari backend
  String _checkInTime = '-- : --';
  String _checkOutTime = '-- : --';
  bool _hasCheckedIn = false;

  // Riwayat absensi terbaru dari backend
  List<Map<String, dynamic>> _attendanceHistory = [];

  // Data pengajuan cuti & sisa kuota dari backend
  List<Map<String, dynamic>> _leaveRequests = [];
  int _leaveBalance = 12;

  // State untuk Notifikasi Karyawan
  List<Map<String, dynamic>> _notifications = [];
  int _unreadNotifCount = 0;

  Position? _currentPosition;
  bool _isLocating = true;
  String _geofenceStatus = 'Mendeteksi lokasi Anda...';
  String _locationDetails = 'Mencari sinyal GPS...';

  // Live Geofence Settings from Backend
  double _officeLatitude = -6.2000;
  double _officeLongitude = 106.8166;
  double _officeRadius = 150.0;
  String _officeName = 'Kantor Pusat';
  List<dynamic> _geofenceList = [];

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _fetchAttendanceHistory();
    _fetchLeaveData();
    _fetchNotifications();
  }

  Future<void> _fetchGeofenceSettings() async {
    try {
      final response = await http.get(
        Uri.parse('http://10.41.159.137:8000/api/v1/master/geofences'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _geofenceList = data;
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal mengambil data geofence: $e');
    }
  }

  Future<void> _determinePosition() async {
    await _fetchGeofenceSettings();
    
    bool serviceEnabled;
    LocationPermission permission;

    setState(() {
      _isLocating = true;
      _geofenceStatus = 'Mendeteksi lokasi Anda...';
      _locationDetails = 'Mencari sinyal GPS...';
    });

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _geofenceStatus = 'GPS Nonaktif';
          _locationDetails = 'Silakan aktifkan GPS perangkat Anda.';
          _isLocating = false;
        });
        _showLocationServiceDialog();
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _geofenceStatus = 'Akses GPS Ditolak';
            _locationDetails = 'Silakan aktifkan GPS perangkat Anda.';
            _isLocating = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Akses lokasi ditolak. Silakan aktifkan izin lokasi untuk absensi.'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _geofenceStatus = 'GPS Diblokir';
          _locationDetails = 'Izinkan GPS melalui Pengaturan sistem.';
          _isLocating = false;
        });
        _showAppSettingsDialog();
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Hitung jarak ke semua geofence dan cari yang terdekat
      double minDistance = double.infinity;
      Map<String, dynamic>? closestGeofence;

      for (var geofence in _geofenceList) {
        final double lat = (geofence['latitude'] as num).toDouble();
        final double lng = (geofence['longitude'] as num).toDouble();
        final double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          lat,
          lng,
        );
        if (distance < minDistance) {
          minDistance = distance;
          closestGeofence = geofence;
        }
      }

      setState(() {
        _currentPosition = position;
        _isLocating = false;
        
        if (closestGeofence != null) {
          final double radius = (closestGeofence['radius_meters'] as num).toDouble();
          final String name = closestGeofence['name'] ?? 'Kantor';
          final bool inRange = minDistance <= radius;

          _officeLatitude = (closestGeofence['latitude'] as num).toDouble();
          _officeLongitude = (closestGeofence['longitude'] as num).toDouble();
          _officeRadius = radius;
          _officeName = name;

          if (inRange) {
            _geofenceStatus = 'Terdeteksi di area: $name';
            _locationDetails = 'Jarak: ${minDistance.toStringAsFixed(1)}m (Dalam radius sah)';
          } else {
            _geofenceStatus = 'Berada di luar area kantor';
            _locationDetails = 'Terdekat: $name (Jarak: ${(minDistance/1000).toStringAsFixed(2)} km)';
          }
        } else {
          _geofenceStatus = 'Tidak ada area geofence';
          _locationDetails = 'Hubungi administrator untuk mengatur area kantor.';
        }
      });
    } catch (e) {
      setState(() {
        _geofenceStatus = 'Gagal memuat lokasi';
        _locationDetails = 'Error: $e';
        _isLocating = false;
      });
    }
  }

  Future<void> _fetchAttendanceHistory() async {
    try {
      final response = await http.get(
        Uri.parse('http://10.41.159.137:8000/api/v1/attendance/logs?user_id=${UserSession.userId}'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        final List<Map<String, dynamic>> formattedLogs = [];
        final List<String> days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
        final List<String> months = [
          'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 
          'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
        ];
        
        for (var log in data) {
          final DateTime scannedAt = DateTime.parse(log['scanned_at']).toLocal();
          
          final String dayName = days[scannedAt.weekday - 1];
          final String monthName = months[scannedAt.month - 1];
          final String formattedDate = '$dayName, ${scannedAt.day} $monthName ${scannedAt.year}';
          
          final String hourStr = scannedAt.hour.toString().padLeft(2, '0');
          final String minuteStr = scannedAt.minute.toString().padLeft(2, '0');
          final String formattedTime = '$hourStr:$minuteStr WIB';
          
          formattedLogs.add({
            'date': formattedDate,
            'time': formattedTime,
            'status': log['status'] ?? 'Tepat Waktu',
            'isValid': log['is_valid'] ?? true,
            'location': log['geofence_name'] ?? 'Kantor',
          });
        }
        
        if (mounted) {
          setState(() {
            _attendanceHistory = formattedLogs;
            
            // Cari log hari ini
            final today = DateTime.now();
            final todayLogs = formattedLogs.where((log) {
              return log['date'].contains('${today.day} ${months[today.month - 1]} ${today.year}');
            }).toList();
            
            if (todayLogs.isNotEmpty) {
              final firstLog = todayLogs.last;
              _checkInTime = firstLog['time'];
              _hasCheckedIn = true;
              
              if (todayLogs.length > 1) {
                final lastLog = todayLogs.first;
                _checkOutTime = lastLog['time'];
              } else {
                _checkOutTime = '-- : --';
              }
            } else {
              _checkInTime = '-- : --';
              _checkOutTime = '-- : --';
              _hasCheckedIn = false;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal mengambil riwayat absensi: $e');
    }
  }

  Future<void> _fetchLeaveData() async {
    try {
      final balanceResponse = await http.get(
        Uri.parse('http://10.41.159.137:8000/api/v1/leaves/balance?user_id=${UserSession.userId}'),
      );
      if (balanceResponse.statusCode == 200) {
        final balanceData = jsonDecode(balanceResponse.body);
        final int total = balanceData['total_quota'] ?? 12;
        final int used = balanceData['used_quota'] ?? 0;
        if (mounted) {
          setState(() {
            _leaveBalance = total - used;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _leaveBalance = 12;
          });
        }
      }
      
      final listResponse = await http.get(
        Uri.parse('http://10.41.159.137:8000/api/v1/leaves/me?user_id=${UserSession.userId}'),
      );
      if (listResponse.statusCode == 200) {
        final List<dynamic> listData = jsonDecode(listResponse.body);
        
        final List<Map<String, dynamic>> formattedRequests = [];
        final List<String> months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 
          'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'
        ];
        
        for (var req in listData) {
          final DateTime start = DateTime.parse(req['start_date']);
          final DateTime end = DateTime.parse(req['end_date']);
          final int days = end.difference(start).inDays + 1;
          
          final String formattedRange = '${start.day} ${months[start.month - 1]} - ${end.day} ${months[end.month - 1]} ${end.year}';
          
          formattedRequests.add({
            'date': formattedRange,
            'days': days,
            'status': req['status'] ?? 'Pending',
            'reason': req['reason'] ?? '',
          });
        }
        
        if (mounted) {
          setState(() {
            _leaveRequests = formattedRequests;
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal mengambil data cuti: $e');
    }
  }

  /// Mengambil semua notifikasi karyawan secara dinamis dari database
  Future<void> _fetchNotifications() async {
    try {
      final response = await http.get(
        Uri.parse('http://10.41.159.137:8000/api/v1/users/${UserSession.userId}/notifications'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _notifications = List<Map<String, dynamic>>.from(data);
            _unreadNotifCount = _notifications.where((n) => n['is_read'] == false).length;
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal mengambil notifikasi: $e');
    }
  }

  /// Menandai satu notifikasi sebagai sudah dibaca
  Future<void> _markNotificationAsRead(int notifId) async {
    try {
      final response = await http.put(
        Uri.parse('http://10.41.159.137:8000/api/v1/users/notifications/$notifId/read'),
      );
      if (response.statusCode == 200) {
        _fetchNotifications();
      }
    } catch (e) {
      debugPrint('Gagal menandai notifikasi dibaca: $e');
    }
  }

  /// Menampilkan dialog detail isi notifikasi
  void _showNotificationDetailDialog(Map<String, dynamic> notif) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            notif['title'],
            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), fontSize: 16),
          ),
          content: Text(
            notif['message'],
            style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF4A4A4A), height: 1.5, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// Menampilkan lembar notifikasi interaktif (Bottom Sheet) dengan desain monokrom/premium
  void _showNotificationsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Handle Bar
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    
                    // Title Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'PEMBERITAHUAN',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          if (_unreadNotifCount > 0)
                            TextButton(
                              onPressed: () async {
                                for (var n in _notifications) {
                                  if (!n['is_read']) {
                                    await _markNotificationAsRead(n['id']);
                                  }
                                }
                                setModalState(() {});
                              },
                              child: const Text(
                                'BACA SEMUA',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF121212),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFFE9ECEF), height: 1),
                    
                    // Notification Content List
                    Expanded(
                      child: _notifications.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF8F9FA),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.notifications_off_outlined,
                                      size: 40,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Belum Ada Pemberitahuan',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Semua pengajuan cuti dan status absensi Anda\nakan diinfokan langsung di sini.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(24),
                              itemCount: _notifications.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final notif = _notifications[index];
                                final isRead = notif['is_read'] ?? false;
                                
                                Color iconColor = const Color(0xFF1A73E8);
                                Color bgColor = const Color(0xFFE8F0FE);
                                IconData icon = Icons.info_outline_rounded;
                                
                                if (notif['title'].contains('Disetujui')) {
                                  iconColor = const Color(0xFF10B981);
                                  bgColor = const Color(0xFFE6F4EA);
                                  icon = Icons.check_circle_outline_rounded;
                                } else if (notif['title'].contains('Ditolak')) {
                                  iconColor = const Color(0xFFEF4444);
                                  bgColor = const Color(0xFFFCE8E6);
                                  icon = Icons.error_outline_rounded;
                                } else if (notif['title'].contains('Terkirim')) {
                                  iconColor = const Color(0xFFF59E0B);
                                  bgColor = const Color(0xFFFEF3C7);
                                  icon = Icons.send_rounded;
                                }
                                
                                return InkWell(
                                  onTap: () async {
                                    if (!isRead) {
                                      await _markNotificationAsRead(notif['id']);
                                      setModalState(() {});
                                    }
                                    _showNotificationDetailDialog(notif);
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isRead ? Colors.white : const Color(0xFFF8F9FA),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isRead ? const Color(0xFFE9ECEF) : iconColor.withOpacity(0.3),
                                        width: isRead ? 1.0 : 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            icon,
                                            color: iconColor,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      notif['title'],
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: isRead ? FontWeight.bold : FontWeight.w900,
                                                        color: const Color(0xFF1A1A1A),
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (!isRead)
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color: iconColor,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                notif['message'],
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                                  color: isRead ? const Color(0xFF7A7A7A) : const Color(0xFF4A4A4A),
                                                  height: 1.4,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: const [
              Icon(Icons.location_off_rounded, color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 12),
              Text(
                'Aktifkan GPS Anda',
                style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
          content: const Text(
            'Layanan lokasi (GPS) pada perangkat Anda dinonaktifkan.\n\n'
            'Silakan aktifkan GPS perangkat Anda agar aplikasi dapat memverifikasi wilayah Geofence kantor.',
            style: TextStyle(fontWeight: FontWeight.w500, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('BATAL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await Geolocator.openLocationSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF121212),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('AKTIFKAN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAppSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: const [
              Icon(Icons.security_rounded, color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 12),
              Text(
                'Izin GPS Diblokir',
                style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
          content: const Text(
            'Akses GPS untuk aplikasi ini diblokir secara permanen.\n\n'
            'Silakan aktifkan izin lokasi secara manual di menu Pengaturan Aplikasi.',
            style: TextStyle(fontWeight: FontWeight.w500, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('BATAL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await Geolocator.openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF121212),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('BUKA PENGATURAN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    List<String> nameParts = name.trim().split(' ');
    if (nameParts.length > 1) {
      return '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    }
    return nameParts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            _buildDashboardPage(),
            _buildHistoryPage(),
            _buildLeavePage(),
            _buildProfilePage(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFE9ECEF), width: 1.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF121212),
          unselectedItemColor: const Color(0xFF7A7A7A),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Beranda',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              activeIcon: Icon(Icons.history_toggle_off_rounded),
              label: 'Riwayat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today_rounded),
              label: 'Cuti',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }

  String _getFormattedTodayDate() {
    final today = DateTime.now();
    final List<String> days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final List<String> months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${days[today.weekday - 1]}, ${today.day} ${months[today.month - 1]} ${today.year}';
  }

  void _showGeofenceDetailsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Row(
            children: const [
              Icon(Icons.apartment_rounded, color: Color(0xFF121212), size: 26),
              SizedBox(width: 12),
              Text(
                'Informasi Kantor',
                style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailItem('Nama Area', _officeName),
              const SizedBox(height: 12),
              _buildDetailItem('Radius Aman', '${_officeRadius.toStringAsFixed(0)} Meter'),
              const SizedBox(height: 12),
              _buildDetailItem('Latitude Kantor', _officeLatitude.toString()),
              const SizedBox(height: 12),
              _buildDetailItem('Longitude Kantor', _officeLongitude.toString()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('TUTUP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailItem(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
        ),
      ],
    );
  }

  Widget _buildRecentActivityWidget() {
    final today = DateTime.now();
    final List<String> months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final todayLogs = _attendanceHistory.where((log) {
      return log['date'].contains('${today.day} ${months[today.month - 1]} ${today.year}');
    }).toList();

    if (todayLogs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(Icons.fingerprint_rounded, size: 36, color: Colors.grey[300]),
            const SizedBox(height: 10),
            const Text(
              'Belum Ada Aktivitas',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 4),
            Text(
              'Catatan absensi Anda hari ini akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: todayLogs.length > 3 ? 3 : todayLogs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final log = todayLogs[index];
        final isLate = log['status'] == 'Terlambat';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isLate ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isLate ? Icons.timer_outlined : Icons.check_circle_outline_rounded,
                      color: isLate ? const Color(0xFFD97706) : const Color(0xFF10B981),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log['status'] ?? 'Hadir',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1A1A1A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        log['location'] ?? 'Kantor',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                log['time'] ?? '--:--',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF121212)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== PAGE 1: DASHBOARD ====================
  Widget _buildDashboardPage() {
    final todayStr = _getFormattedTodayDate();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branded Corporate App Bar Logo
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/clockit_logo.png',
                  width: 24,
                  height: 24,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Clockit',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF121212),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Header Karyawan
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _getInitials(UserSession.fullName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todayStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        UserSession.fullName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              GestureDetector(
                onTap: _showNotificationsBottomSheet,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        size: 20,
                        color: Color(0xFF121212),
                      ),
                    ),
                    if (_unreadNotifCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$_unreadNotifCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // GIANT PREMIUM PRESENSI CARD (The core WOW factor!)
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ScanAttendanceScreen(
                  cachedLatitude: _currentPosition?.latitude,
                  cachedLongitude: _currentPosition?.longitude,
                )),
              ).then((value) {
                if (value == true) {
                  _fetchAttendanceHistory();
                  _fetchLeaveData();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF232526), Color(0xFF414345)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF121212).withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                            SizedBox(width: 6),
                            Text(
                              'SIAP PRESENSI',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white60, size: 14),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'PINDAI QR PRESENSI',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ketuk untuk melakukan absen masuk / pulang',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Info Lokasi & Geofence (Subtle Bordered Card)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isLocating 
                        ? const Color(0xFFF3F4F6) 
                        : (_geofenceStatus.contains('Kantor') ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2)), 
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.location_on_rounded, 
                    color: _isLocating 
                        ? Colors.grey 
                        : (_geofenceStatus.contains('Kantor') ? const Color(0xFF10B981) : const Color(0xFFEF4444)), 
                    size: 20
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isLocating ? 'Mendeteksi Koordinat...' : _geofenceStatus,
                        style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _locationDetails,
                        style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _determinePosition,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
                    ),
                    child: _isLocating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF121212))),
                          )
                        : const Icon(Icons.sync_rounded, color: Color(0xFF121212), size: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Stats Kehadiran (In & Out side-by-side)
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.login_rounded, color: Color(0xFF10B981), size: 16),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'JAM MASUK',
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _checkInTime,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 16),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'JAM PULANG',
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _checkOutTime,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Grid of Services / Quick Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Layanan Utama',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
              Text(
                'Menu Karyawan',
                style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LeaveRequestScreen()),
                    ).then((value) {
                      _fetchLeaveData();
                      _fetchNotifications();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF121212)),
                        SizedBox(width: 10),
                        Text(
                          'AJUKAN CUTI',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF121212), letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _showGeofenceDetailsDialog();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.map_rounded, size: 18, color: Color(0xFF121212)),
                        SizedBox(width: 10),
                        Text(
                          'INFO KANTOR',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF121212), letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Recent Activity Section (The best space filler!)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Aktivitas Hari Ini',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _currentIndex = 1; // Pindah ke halaman riwayat
                  });
                },
                child: Text(
                  'Lihat Semua',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRecentActivityWidget(),
        ],
      ),
    );
  }

  // ==================== PAGE 2: RIWAYAT ABSENSI ====================
  Widget _buildHistoryPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Riwayat Kehadiran',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 8),
          Text(
            'Daftar lengkap pencatatan jam presensi Anda.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _attendanceHistory.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final log = _attendanceHistory[index];
              final isLate = log['status'] == 'Terlambat';

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isLate ? const Color(0xFFFFFbeb) : const Color(0xFFecfdf5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isLate ? Icons.alarm_rounded : Icons.check_circle_outline_rounded,
                            color: isLate ? const Color(0xFFD97706) : const Color(0xFF10B981),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log['date'],
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              log['location'],
                              style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          log['time'],
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log['status'],
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isLate ? const Color(0xFFD97706) : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==================== PAGE 3: STATUS CUTI ====================
  Widget _buildLeavePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Manajemen Cuti',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LeaveRequestScreen()),
                  );
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('AJUKAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pantau kuota dan status pengajuan izin/cuti Anda.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),

          // Leave Balance Card QuickView
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SISA KUOTA CUTI TAHUNAN',
                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_leaveBalance Hari',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const Icon(Icons.calendar_month_rounded, color: Colors.white60, size: 36),
              ],
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Riwayat Pengajuan Cuti',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 16),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _leaveRequests.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final req = _leaveRequests[index];
              final isPending = req['status'] == 'Pending';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          req['date'],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A1A1A)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPending ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            req['status'],
                            style: TextStyle(
                              color: isPending ? const Color(0xFFD97706) : const Color(0xFF059669),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Keperluan: ${req['reason']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Durasi: ${req['days']} Hari Kerja',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF121212), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==================== PAGE 4: PROFIL ====================
  Widget _buildProfilePage() {
    return FutureBuilder<String>(
      future: _getSilentDeviceId(),
      builder: (context, snapshot) {
        final deviceId = snapshot.data ?? 'Membaca Device ID...';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Profil Saya',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 24),

              // Profile Card Premium
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: const Color(0xFF121212),
                      child: Text(
                        _getInitials(UserSession.fullName),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      UserSession.fullName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Karyawan Aktif - IT Support',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Hardware Lock status
              Text('KEAMANAN & HARDWARE LOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Status Perangkat Terkunci',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Device ID: $deviceId',
                            style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // Logout Button
              ElevatedButton(
                onPressed: () {
                  _showLogoutConfirmDialog();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: const Text('KELUAR DARI APLIKASI', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLogoutConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('🚪 Konfirmasi Keluar', style: TextStyle(fontWeight: FontWeight.w900)),
          content: const Text(
            'Apakah Anda yakin ingin keluar dari akun Anda?\n'
            'Anda harus masuk kembali dengan kredensial sah.',
            style: TextStyle(fontWeight: FontWeight.w500, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('BATAL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context); // Tutup dialog
                await UserSession.clearSession();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: const Text('KELUAR', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
            )
          ],
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
}
