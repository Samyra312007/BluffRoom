/// App-wide configuration.
///
/// The server address is injected at **compile time** from the environment:
///
/// ```bash
/// flutter run --dart-define=SERVER_URL=https://your-server.com
/// flutter build apk --release --dart-define=SERVER_URL=https://your-server.com
/// ```
///
/// If no SERVER_URL is provided, a local-development fallback is used and the
/// Home screen shows a warning banner so testers are never silently connected
/// to the wrong server.
class AppConfig {
  AppConfig._();

  /// Compile-time server URL (via --dart-define), if provided.
  static const String? _envUrl = bool.hasEnvironment('SERVER_URL')
      ? String.fromEnvironment('SERVER_URL')
      : null;

  /// Fallback used when SERVER_URL is not provided at build time.
  /// `10.0.2.2` is the Android-emulator alias for the host machine's
  /// localhost, which makes `flutter run` work against a local dev server.
  static const String fallbackUrl = 'http://10.0.2.2:3000';

  /// Name of the environment variable, surfaced in diagnostics.
  static const String serverUrlEnvName = 'SERVER_URL';

  static bool get hasExplicitServerUrl => _envUrl != null;

  /// Resolved, normalized base URL of the game server (no trailing slash).
  static String get serverUrl => _normalize(_envUrl);

  /// Normalizes whitespace, trailing slashes, and empty values.
  static String _normalize(String? raw) {
    final url = raw?.trim() ?? '';
    if (url.isEmpty) return fallbackUrl;
    if (url.endsWith('/')) return url.substring(0, url.length - 1);
    return url;
  }

  // ---------------------------------------------------------------- app info
  static const String appName = 'BluffRoom';
  static const String appVersion = '1.0.0';
  static const int appBuildNumber = 1;

  // ------------------------------------------------------- game rule constants
  // These are display/UX hints only. The server is authoritative for all
  // actual rules; the client never validates game outcomes itself.
  static const int minPlayers = 2;
  static const int maxPlayers = 8;
  static const int turnSeconds = 30;
  static const int maxCardsPerPlay = 4;
  static const int minCardsPerPlay = 1;
}
