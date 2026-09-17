import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'controllers/game_controller.dart';
import 'models/game_events.dart';
import 'screens/game_table_screen.dart';
import 'screens/home_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/lobby_screen.dart';
import 'services/game_service.dart';
import 'widgets/challenge_reveal_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  final session = await SessionStore.load();
  final service = GameService(sessionStore: session);
  final controller = GameController(gameService: service, session: session);

  runApp(BluffRoomApp(controller: controller, session: session));
}

/// Root widget owning the app-level phase switch and global chrome.
class BluffRoomApp extends StatefulWidget {
  const BluffRoomApp({super.key, required this.controller, required this.session});

  final GameController controller;
  final SessionStore session;

  @override
  State<BluffRoomApp> createState() => _BluffRoomAppState();
}

enum _AppPhase { home, lobby, table, leaderboard }

class _BluffRoomAppState extends State<BluffRoomApp> {
  _AppPhase _phase = _AppPhase.home;
  ChallengeReveal? _overlayReveal;

  @override
  void initState() {
    super.initState();
    widget.controller.addSnackTarget(_showSnack);
    widget.controller.addListener(_onController);
    // Fire-and-forget: connects and attempts a session-token rejoin.
    widget.controller.connectWithRejoin();
  }

  void _onController() {
    if (!mounted) return;
    final c = widget.controller;

    setState(() {
      if (c.activeReveal != null && c.activeReveal != _overlayReveal) {
        _overlayReveal = c.activeReveal;
      }
      // Cards arrived while in lobby → the server started the game.
      if (c.state.self?.hand.isNotEmpty == true && _phase == _AppPhase.lobby) {
        _phase = _AppPhase.table;
      }
      if (c.leaderboard != null && _phase != _AppPhase.leaderboard) {
        _phase = _AppPhase.leaderboard;
      }
    });

    if (c.kickedMessage != null) {
      _showSnack(c.kickedMessage!);
      setState(() => _phase = _AppPhase.home);
      c.kickedMessage = null;
    }
  }

  void _dismissReveal() {
    setState(() {
      _overlayReveal = null;
      widget.controller.activeReveal = null;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: AppTheme.theme,
      home: Stack(
        children: [
          _buildScreen(),
          if (_overlayReveal != null)
            ChallengeRevealOverlay(reveal: _overlayReveal!, onDismiss: _dismissReveal),
        ],
      ),
    );
  }

  Widget _buildScreen() {
    final c = widget.controller;
    switch (_phase) {
      case _AppPhase.home:
        return HomeScreen(
          controller: c,
          session: widget.session,
          onRoomReady: () => setState(() => _phase = _AppPhase.lobby),
        );
      case _AppPhase.lobby:
        return LobbyScreen(
          controller: c,
          onStart: () => setState(() => _phase = _AppPhase.table),
          onLeave: () => setState(() => _phase = _AppPhase.home),
        );
      case _AppPhase.table:
        return GameTableScreen(
          controller: c,
          onLeaderboard: () => setState(() => _phase = _AppPhase.leaderboard),
          onExit: () => setState(() => _phase = _AppPhase.home),
        );
      case _AppPhase.leaderboard:
        return LeaderboardScreen(
          controller: c,
          onExit: () => setState(() => _phase = _AppPhase.home),
          onRestarted: () => setState(() => _phase = _AppPhase.table),
        );
    }
  }
}
