# mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
## Google Sign-In Setup

This project uses `google_sign_in` for authentication.

### Required configuration

1. Create an OAuth 2.0 Client ID in Google Cloud Console:
   - Type: `Web application`
   - Authorized redirect URIs: leave empty for native mobile sign-in
2. Copy the Web client ID and set it in:
   - `lib/features/auth/config.dart`
   - Replace `'<YOUR_WEB_CLIENT_ID>.apps.googleusercontent.com'`

### Android configuration

- Application ID: `com.absenpro.mobile`
- Debug SHA-1 fingerprint:
  `52:15:3A:20:0E:99:CB:2B:9A:47:26:52:1F:FE:9C:B8:4E:30:F5:F5`

If you use Firebase for Google Sign-In, also place `google-services.json`
inside `android/app/`.

### Common error

- `ApiException: 10` means the Android OAuth client is not configured correctly.
- Check package name, SHA-1, and the web client ID.
