import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:mobile/core/session/user_session.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  
  DateTime? _startDate;
  DateTime? _endDate;
  int _leaveBalance = 12; // Default fallback
  bool _isLoadingBalance = true;
  bool _isSubmitting = false;

  // State untuk File Upload
  PlatformFile? _selectedFile;
  String? _uploadedFileUrl;
  bool _isUploadingFile = false;

  @override
  void initState() {
    super.initState();
    _fetchLeaveBalance();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  /// Mengambil sisa kuota cuti dari backend secara dinamis sesuai user ID
  Future<void> _fetchLeaveBalance() async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.1.7:8000/api/v1/leaves/balance?user_id=${UserSession.userId}'),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _leaveBalance = data['total_quota'] - data['used_quota'];
          _isLoadingBalance = false;
        });
      } else {
        setState(() {
          _isLoadingBalance = false;
        });
      }
    } catch (e) {
      debugPrint('Gagal mengambil kuota cuti: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingBalance = false;
      });
    }
  }

  /// Memilih dan Mengunggah File ke Server FastAPI
  Future<void> _pickAndUploadFile() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      );

      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      setState(() {
        _selectedFile = pickedFile;
        _isUploadingFile = true;
      });

      // Siapkan Multipart Request ke Endpoint Backend FastAPI
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.1.7:8000/api/v1/leaves/upload'),
      );

      if (pickedFile.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          pickedFile.bytes!,
          filename: pickedFile.name,
        ));
      } else if (pickedFile.path != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          pickedFile.path!,
          filename: pickedFile.name,
        ));
      } else {
        throw Exception('Konten berkas tidak dapat dibaca.');
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (!mounted) return;

      setState(() {
        _isUploadingFile = false;
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        setState(() {
          _uploadedFileUrl = data['document_url'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dokumen pendukung berhasil diunggah!'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _selectedFile = null;
          _uploadedFileUrl = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Gagal mengunggah dokumen ke server.'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedFile = null;
        _uploadedFileUrl = null;
        _isUploadingFile = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Terjadi kesalahan saat mengunggah: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Memilih Tanggal Cuti
  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF121212),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  /// Kirim Pengajuan ke Backend FastAPI secara dinamis sesuai user ID
  Future<void> _submitLeave() async {
    if (!_formKey.currentState!.validate() || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Lengkapi semua kolom dan tanggal pengajuan!'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final Map<String, dynamic> payload = {
        'start_date': _startDate!.toIsoformat(),
        'end_date': _endDate!.toIsoformat(),
        'reason': _reasonController.text.trim(),
        'document_url': _uploadedFileUrl,
      };

      final response = await http.post(
        Uri.parse('http://192.168.1.7:8000/api/v1/leaves/?user_id=${UserSession.userId}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      if (response.statusCode == 200) {
        // Tampilkan Dialog Sukses
        _showSuccessDialog();
      } else {
        final data = jsonDecode(response.body);
        final String errorDetail = data['detail'] ?? 'Kuota cuti tidak mencukupi / terjadi kesalahan.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal: $errorDetail'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Gagal terhubung ke server: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.white,
          elevation: 10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F4EA),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                const Text(
                  'Pengajuan Sukses',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Description
                const Text(
                  'Pengajuan cuti/izin Anda berhasil dikirim ke HRD. Silakan pantau status persetujuan secara berkala.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6C757D),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Tutup dialog
                      Navigator.pop(context); // Kembali ke dashboard
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Kembali ke Beranda',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Pengajuan Cuti & Izin', style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. INFO KUOTA CUTI (Card Monokrom)
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
                            'Sisa Kuota Cuti Tahunan',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 6),
                          _isLoadingBalance
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                )
                              : Text(
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

                // 2. PEMILIH TANGGAL (Date Picker Trigger)
                Text('Durasi Cuti / Izin', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _selectDateRange(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.date_range_rounded, color: Color(0xFF7A7A7A), size: 20),
                            const SizedBox(width: 12),
                            Text(
                              _startDate == null || _endDate == null
                                  ? 'Pilih Rentang Tanggal'
                                  : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}  s/d  ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                              style: TextStyle(
                                fontSize: 13,
                                color: _startDate == null ? const Color(0xFF7A7A7A) : const Color(0xFF1A1A1A),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF7A7A7A), size: 14),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 3. ALASAN PENGAJUAN (TextArea)
                Text('Alasan Utama', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 4,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Alasan pengajuan wajib diisi!';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    hintText: 'Tuliskan alasan lengkap pengajuan cuti atau alasan izin sakit Anda...',
                  ),
                ),
                const SizedBox(height: 24),

                // 4. UPLOAD DOKUMEN PENDUKUNG (Premium Picker Widget)
                Text('Dokumen Pendukung / Surat Sakit (Opsional)', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _isUploadingFile ? null : _pickAndUploadFile,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _uploadedFileUrl != null
                            ? const Color(0xFF10B981)
                            : const Color(0xFFE9ECEF),
                        width: 1.5,
                      ),
                    ),
                    child: _isUploadingFile
                        ? Column(
                            children: const [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF121212)),
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Mengunggah Dokumen ke Server...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7A7A7A),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : _uploadedFileUrl != null
                            ? Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE6F4EA),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF10B981),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedFile?.name ?? 'Dokumen Pendukung',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF1A1A1A),
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Dokumen berhasil diunggah secara aman',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF7A7A7A),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _pickAndUploadFile,
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF121212),
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Ganti',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F9FA),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.cloud_upload_outlined,
                                      color: Color(0xFF7A7A7A),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Pilih atau Tarik File Anda',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF1A1A1A),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Mendukung PDF, PNG, JPG, JPEG, DOCX (Maksimal 10MB)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF7A7A7A),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                  ),
                ),
                const SizedBox(height: 48),

                // 5. TOMBOL SUBMIT (Loading Dynamic)
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitLeave,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Kirim Pengajuan Sekarang'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension DateTimeFormatter on DateTime {
  String toIsoformat() {
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}T00:00:00';
  }
}
