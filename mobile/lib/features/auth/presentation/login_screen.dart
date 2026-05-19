import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import '../../dashboard/presentation/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _loginController = LoginController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Tambahkan listener untuk mendengarkan perubahan status login
    _loginController.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _loginController.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (_loginController.state == LoginState.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Login Sukses! Perangkat Berhasil Diverifikasi.'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Navigasi ke halaman utama / dashboard karyawan
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const EmployeeHomeScreen()),
      );
    } else if (_loginController.state == LoginState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loginController.errorMessage),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _submitLogin() {
    if (_formKey.currentState!.validate()) {
      _loginController.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
    }
  }

  /// Membuka bottom sheet interaktif untuk pemulihan password lewat OTP
  void _showForgotPasswordDialog() {
    final emailResetController = TextEditingController();
    final otpController = TextEditingController();
    final newPasswordController = TextEditingController();
    bool isOtpSent = false;
    bool isDialogLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendOtp() async {
              if (emailResetController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Silakan masukkan email Anda terlebih dahulu.'),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              
              setDialogState(() => isDialogLoading = true);
              try {
                final response = await http.post(
                  Uri.parse('http://10.41.159.137:8000/api/v1/auth/forgot-password'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'email': emailResetController.text.trim()}),
                );
                
                if (response.statusCode == 200) {
                  setDialogState(() {
                    isOtpSent = true;
                    isDialogLoading = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Kode OTP berhasil dikirim ke email Anda!'),
                      backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  final data = jsonDecode(response.body);
                  throw Exception(data['detail'] ?? 'Gagal mengirim OTP.');
                }
              } catch (e) {
                setDialogState(() => isDialogLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Gagal: ${e.toString().replaceAll('Exception: ', '')}'),
                    backgroundColor: const Color(0xFFEF4444),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }

            Future<void> resetPassword() async {
              if (otpController.text.trim().length != 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Masukkan 6 digit kode OTP secara lengkap.'),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (newPasswordController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Masukkan kata sandi baru Anda.'),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              setDialogState(() => isDialogLoading = true);
              try {
                final response = await http.post(
                  Uri.parse('http://10.41.159.137:8000/api/v1/auth/reset-password'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'email': emailResetController.text.trim(),
                    'otp': otpController.text.trim(),
                    'new_password': newPasswordController.text,
                  }),
                );

                if (response.statusCode == 200) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🎉 Password berhasil diperbarui! Silakan login kembali.'),
                      backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  final data = jsonDecode(response.body);
                  throw Exception(data['detail'] ?? 'Gagal reset password.');
                }
              } catch (e) {
                setDialogState(() => isDialogLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Gagal: ${e.toString().replaceAll('Exception: ', '')}'),
                    backgroundColor: const Color(0xFFEF4444),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 30,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isOtpSent ? 'Atur Ulang Sandi' : 'Lupa Kata Sandi',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isOtpSent 
                        ? 'Masukkan 6 digit kode OTP dari email Anda dan tentukan password baru.'
                        : 'Masukkan email terdaftar Anda untuk menerima kode OTP pemulihan.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF7A7A7A),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!isOtpSent) ...[
                    Text(
                      'ALAMAT EMAIL',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A1A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailResetController,
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        hintText: 'nama@perusahaan.com',
                        prefixIcon: Icon(Icons.email_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isDialogLoading ? null : sendOtp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: isDialogLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('KIRIM KODE OTP'),
                    ),
                  ] else ...[
                    Text(
                      'KODE OTP (6 DIGIT)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A1A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 5),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: '••••••',
                        prefixIcon: Icon(Icons.pin_outlined, size: 18),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'KATA SANDI BARU',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A1A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        hintText: 'Masukkan sandi baru',
                        prefixIcon: Icon(Icons.lock_outline, size: 18),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isDialogLoading ? null : resetPassword,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: isDialogLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('SIMPAN & ATUR ULANG'),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Double Ring Brand Logo
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: Image.asset(
                        'assets/images/clockit_logo.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Subtitle & Title Header
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBECEF),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 10, color: Color(0xFF495057)),
                        const SizedBox(width: 6),
                        Text(
                          'PRESENSI ONLINE',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF495057),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Clockit',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1A1A1A),
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Silakan login untuk mencatat kehadiran Anda.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF7A7A7A),
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // 3. Premium Glassmorphic Form Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.015),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Input Email
                        Text(
                          'ALAMAT EMAIL',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A1A),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Email wajib diisi!';
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                              return 'Format email tidak valid!';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'nama@perusahaan.com',
                            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF7A7A7A), fontWeight: FontWeight.w500),
                            prefixIcon: const Icon(Icons.email_outlined, size: 18),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Input Password Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'KATA SANDI',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1A1A1A),
                                letterSpacing: 0.5,
                              ),
                            ),
                            GestureDetector(
                              onTap: _showForgotPasswordDialog,
                              child: Text(
                                'Lupa Sandi?',
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF121212),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Kata sandi wajib diisi!';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF7A7A7A), fontWeight: FontWeight.w500),
                            prefixIcon: const Icon(Icons.lock_outline, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Submit Button
                        AnimatedBuilder(
                          animation: _loginController,
                          builder: (context, child) {
                            final isLoading = _loginController.state == LoginState.loading;
                            
                            return ElevatedButton(
                              onPressed: isLoading ? null : _submitLogin,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      'LOGIN',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            );
                          },
                        ),

                        const SizedBox(height: 20),
                        
                        // OR divider
                        Row(
                          children: [
                            const Expanded(child: Divider(color: Color(0xFFE9ECEF), thickness: 1)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'ATAU MASUK DENGAN',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFADB5BD),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider(color: Color(0xFFE9ECEF), thickness: 1)),
                          ],
                        ),
                        
                        const SizedBox(height: 20),

                        // Google SSO Button
                        AnimatedBuilder(
                          animation: _loginController,
                          builder: (context, child) {
                            final isLoading = _loginController.state == LoginState.loading;
                            
                            return OutlinedButton.icon(
                              onPressed: isLoading ? null : () => _loginController.loginWithGoogle(),
                              icon: Image.network(
                                'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
                                height: 16,
                                width: 16,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.g_mobiledata_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                              ),
                              label: Text(
                                'MASUK DENGAN GOOGLE',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF495057),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                side: const BorderSide(color: Color(0xFFCED4DA), width: 1.5),
                                backgroundColor: Colors.white,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Premium Security Binding Seal
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE9ECEF), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.security_outlined,
                          size: 16,
                          color: Color(0xFF495057),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'ID Perangkat Anda terikat otomatis setelah login pertama.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: const Color(0xFF7A7A7A),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
