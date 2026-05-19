/// Konfigurasi Google Sign-In untuk aplikasi mobile.
///
/// Ganti nilai `googleSignInClientId` dengan Web client ID OAuth 2.0
/// yang terdaftar di Google Cloud Console.
///
/// Untuk Google Sign-In Android, pastikan:
/// - package name: com.clockit.mobile
/// - SHA-1 fingerprint debug: 52:15:3A:20:0E:99:CB:2B:9A:47:26:52:1F:FE:9C:B8:4E:30:F5:F5
///
/// Jika menggunakan Firebase, letakkan file `google-services.json`
/// di `android/app/`.
const String googleSignInClientId =
    '292635098416-mb34jep2ip09rle65lhljd818h1a65k9.apps.googleusercontent.com';

const String googleSignInAndroidPackageName = 'com.clockit.mobile';
const String googleSignInAndroidDebugSha1 =
    '52:15:3A:20:0E:99:CB:2B:9A:47:26:52:1F:FE:9C:B8:4E:30:F5:F5';
