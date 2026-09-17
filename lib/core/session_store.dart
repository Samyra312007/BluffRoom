import 'package:shared_preferences/shared_preferences.dart';

/// Persists the session token and player name across app restarts.
///
/// The token lets the server re-attach a returning client to its seat without
/// re-joining. It is stored in app-private storage via SharedPreferences.
class SessionStore {
  static const String _kToken = 'session_token';
  static const String _kName = 'player_name';
  static const String _kRoom = 'last_room_code';

  final SharedPreferences _prefs;

  SessionStore(this._prefs);

  static Future<SessionStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionStore(prefs);
  }

  String? get token => _prefs.getString(_kToken);
  String? get playerName => _prefs.getString(_kName);
  String? get lastRoomCode => _prefs.getString(_kRoom);

  Future<void> save({String? token, String? playerName, String? lastRoomCode}) async {
    if (token != null) {
      if (token.isEmpty) {
        await _prefs.remove(_kToken);
      } else {
        await _prefs.setString(_kToken, token);
      }
    }
    if (playerName != null) {
      if (playerName.isEmpty) {
        await _prefs.remove(_kName);
      } else {
        await _prefs.setString(_kName, playerName);
      }
    }
    if (lastRoomCode != null) {
      if (lastRoomCode.isEmpty) {
        await _prefs.remove(_kRoom);
      } else {
        await _prefs.setString(_kRoom, lastRoomCode);
      }
    }
  }

  Future<void> clearSession() => save(token: '');
}
