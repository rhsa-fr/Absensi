
# REQUIREMENT PRODUCT DOCUMENT (RPD)
**Versi:** 2.0.0
**Tanggal:** 19 Mei 2026
**Proyek:** Sistem Absensi Terintegrasi (Dynamic QR Code, Geofencing, dan Device Binding)

## 1. EXECUTIVE SUMMARY
**Latar Belakang:** Sistem absensi konvensional memicu masalah antrean pada jam sibuk dan rentan manipulasi.
**Masalah yang Ingin Diselesaikan:** Praktik kecurangan absensi, kesulitan pemantauan real-time oleh manajemen, dan inefisiensi pengelolaan dokumen izin/cuti.
**Tujuan Utama:** Membangun sistem absensi terintegrasi yang akurat, aman, dan sangat hemat biaya operasional. Sistem ini memadukan pemindaian Dynamic QR Code yang berubah secara berkala, pelacakan lokasi (Geofencing), dan pengikatan perangkat (Device Binding) untuk memastikan pengguna benar-benar berada di lokasi kerja menggunakan perangkat yang sah.

## 2. SUCCESS METRICS (KPI)
* **Kategori Performance:** Waktu pemrosesan absensi (dari scan QR hingga respons sukses) di bawah 2 detik.
* **Kategori Security:** Persentase lolosnya kecurangan lokasi (Fake GPS) atau titip absen (berbagi foto QR / menggunakan HP lain) adalah 0 persen.
* **Kategori Reliability:** System Uptime untuk API dan Web Dashboard mencapai 99.9 persen.
* **Kategori UX:** Tingkat adopsi dan keberhasilan karyawan menggunakan aplikasi pada minggu pertama di atas 95 persen.

## 3. USER PERSONA
**Pengguna Aplikasi Mobile (Karyawan atau Mahasiswa)**
* **Karakteristik:** Mobilitas tinggi, menggunakan berbagai jenis smartphone (Android/iOS).
* **Kebutuhan:** Melakukan clock-in dan clock-out dengan cepat tanpa antre, memantau sisa cuti, dan mengajukan izin langsung dari smartphone.

**Pengguna Web Dashboard (Admin atau HR)**
* **Karakteristik:** Bekerja di depan komputer, mengelola operasional data besar.
* **Kebutuhan:** Menampilkan Dynamic QR Code di layar monitor lobi kantor, memantau kehadiran real-time, mengatur titik geofencing, menyetujui izin, mengelola pengikatan perangkat (reset device), dan mengekspor laporan bulanan.

## 4. FUNCTIONAL REQUIREMENTS (MOBILE APP - USER)
1. **Silent Auto-Binding:** Saat pertama kali login, aplikasi akan secara diam-diam merekam identitas unik perangkat (Device ID/IMEI) dan mengikatnya dengan akun pengguna.
2. **QR Code Scanner:** Aplikasi memiliki fitur pemindai kamera bawaan untuk membaca Dynamic QR Code yang ditampilkan di layar fasilitas kantor.
3. **Validasi 3 Lapis (QR + GPS + Device ID):** Saat proses scan QR terjadi, aplikasi wajib membaca koordinat GPS perangkat dan Device ID. Absensi hanya dinyatakan valid jika Token QR belum kadaluarsa, posisi pengguna berada di dalam radius geofence, DAN Device ID cocok dengan yang terdaftar.
4. **Pengajuan Izin/Sakit/Cuti:** Formulir digital untuk memilih tanggal absen, alasan, dan fitur unggah dokumen pendukung (PDF/JPG surat dokter), yang terintegrasi dengan pengecekan kuota cuti.
5. **Dashboard Riwayat Pribadi:** Tampilan kalender atau daftar riwayat absensi bulanan pengguna dengan status Hadir, Terlambat, Izin, Sakit, atau Alpha.

## 5. FUNCTIONAL REQUIREMENTS (WEB APP - ADMIN)
1. **Dynamic QR Code Generator:** Halaman khusus pada dasbor untuk menampilkan QR Code. QR Code ini mengandung token terenkripsi yang otomatis refresh (berubah bentuk) setiap 15 detik.
2. **Manajemen Data Master & Role:** Fitur CRUD untuk data Karyawan, Departemen, aturan Shift Kerja (toleransi keterlambatan), dan hak akses (Role).
3. **Manajemen Geofencing:** Antarmuka peta digital interaktif tempat Admin menandai titik koordinat pusat (Pin) dan mengatur batas radius sah (misal: radius 50 meter).
4. **Manajemen Perangkat (Device Reset):** Fitur untuk menghapus ikatan perangkat pada akun karyawan tertentu jika karyawan tersebut kehilangan HP atau mengganti perangkat.
5. **Approval Workflow:** Modul untuk meninjau pengajuan izin/cuti dari karyawan untuk disetujui (Approve) atau ditolak (Reject).
6. **Laporan dan Export:** Fitur filter pencarian data absensi yang dapat diekspor menjadi format Excel, CSV, atau PDF.

## 6. EDGE CASES DAN ERROR HANDLING
* **Pencegahan Titip Absen via Berbagi Foto QR Code & Perangkat Lain**
  * **Solusi Sistemik:** Validasi 3 Lapis. Meskipun Karyawan A memotret layar QR di kantor dan mengirimnya ke Karyawan B di rumah, absensi Karyawan B akan otomatis ditolak karena koordinat GPS Karyawan B berada jauh di luar radius kantor. Jika Karyawan A memberikan akunnya ke Karyawan B yang sudah ada di kantor, sistem tetap menolak karena Device ID Karyawan B tidak terdaftar untuk akun Karyawan A.
* **Pencegahan Aplikasi Pihak Ketiga (Fake GPS / Mock Location)**
  * **Solusi Sistemik:** Aplikasi mobile klien wajib mendeteksi bendera sistem OS seperti properti isMockLocation (Android). Jika terdeteksi aktif, aplikasi harus memblokir proses scan QR dan menampilkan pesan peringatan untuk mematikan aplikasi Fake GPS.
* **Kondisi Offline (Hilang Sinyal Internet Saat Absen)**
  * **Solusi Sistemik:** Jika koneksi gagal, aplikasi akan mengemas Payload (Token QR, Koordinat GPS, dan Device ID) dengan stempel waktu internal (timestamp) secara terenkripsi ke dalam penyimpanan lokal perangkat. Saat koneksi stabil kembali, background service akan menyinkronkannya ke server.
* **Penggantian Perangkat Karyawan**
  * **Solusi Sistemik:** Karyawan melapor ke HR. HR menekan tombol "Reset Device" pada dashboard. Karyawan login kembali di HP baru, dan sistem melakukan auto-binding pada HP baru tersebut.

## 7. TECHNICAL REQUIREMENTS
* **Mobile Frontend:** Flutter (Dart) untuk aplikasi lintas platform iOS dan Android.
* **Web Frontend:** Next.js (React) untuk Web Admin dan layar penampil Dynamic QR Code.
* **Backend System dan API:** FastAPI (Python) untuk memproses ribuan request konkueren saat jam sibuk masuk kerja.
* **Database:** PostgreSQL dipadukan dengan ekstensi PostGIS, sangat andal untuk menghitung kalkulasi jarak koordinat geografis (geofencing) secara presisi dan cepat.
* **Cloud Storage:** Amazon S3 atau Google Cloud Storage hanya untuk menyimpan dokumen lampiran izin.

## 8. ALUR KERJA SISTEM (SYSTEM WORKFLOW)

![Alur Kerja](Alur.jpg)

**A. Fase Persiapan & Device Binding**
1. HR membuatkan akun dengan password default.
2. Karyawan login pertama kali di aplikasi mobile.
3. Aplikasi melakukan Silent Auto-Binding (mengunci akun ke Device ID HP tersebut).

**B. Alur Absensi Harian**
1. Admin menampilkan halaman QR Code Dinamis (refresh setiap 15 detik) di layar monitor lobi kantor.
2. Karyawan membuka aplikasi mobile, menekan tombol "Scan Absen".
3. Aplikasi membuka kamera dan mengunci titik koordinat GPS serta membaca Device ID.
4. Karyawan memindai QR Code di layar.
5. Server melakukan Validasi 3 Lapis (QR Valid, GPS Radius Sah, Device ID Cocok).
6. Server mencocokkan waktu absen dengan Shift Kerja untuk menentukan Tepat Waktu/Terlambat.
7. Aplikasi menampilkan notifikasi sukses.

**C. Alur Pengajuan Cuti**
1. Karyawan memilih menu Pengajuan Cuti.
2. Sistem mengecek sisa kuota cuti tahunan (Leave Balance). Jika habis, tombol dinonaktifkan.
3. Jika kuota ada, karyawan mengisi form dan mengunggah dokumen.
4. HR meninjau dan menyetujui pengajuan.
5. Kuota cuti karyawan langsung terpotong.

## 9. ENTITY RELATIONSHIP DIAGRAM (ERD)

![ERD](ERD%20AS.jpg)

**Penjelasan Struktur Data (Skala Enterprise):**
* **ROLES & DEPARTMENTS:** Mengelola hierarki dan struktur organisasi perusahaan.
* **SHIFTS:** Mendefinisikan aturan jam kerja dan toleransi keterlambatan secara fleksibel.
* **USERS:** Entitas utama untuk otentikasi.
* **USER_DEVICES:** Komponen krusial untuk fitur Hardware Locking (Device Binding) yang mencegah satu HP untuk banyak akun.
* **ATTENDANCES:** Mencatat riwayat validasi, posisi koordinat aktual (untuk mencegah fraud), serta ID perangkat yang dipakai.
* **LEAVE_BALANCES & LEAVE_REQUESTS:** Sistem kuota cuti otomatis yang terintegrasi langsung dengan permintaan.
* **GEOFENCES:** Definisi zona spasial sah untuk validasi kehadiran.
