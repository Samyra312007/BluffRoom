import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../controllers/game_controller.dart';
import '../services/game_service.dart' show kShareMessageTemplate;
import '../widgets/connection_badge.dart';
import '../widgets/felt_background.dart';

/// Waiting room before the game starts.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.controller,
    required this.onStart,
    required this.onLeave,
  });

  final GameController controller;
  final VoidCallback onStart;
  final VoidCallback onLeave;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    // Auto-advance on server-confirmed start.
    if (widget.controller.state.self?.hand.isNotEmpty == true) {
      widget.onStart();
    }
    setState(() {});
  }

  void _share() {
    final msg = kShareMessageTemplate.replaceAll('%CODE%', widget.controller.roomCode);
    SharePlus.instance.share(ShareParams(text: msg, title: 'BluffRoom'));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.controller.roomCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Room code ${widget.controller.roomCode} copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final players = c.state.players;
    final canStart = c.isHost && players.length >= AppConfig.minPlayers;

    return FeltBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Lobby'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: ConnectionBadge(state: c.connState)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Giant room code.
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.45), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Text('ROOM CODE', style: TextStyle(color: AppTheme.textDim, letterSpacing: 3, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      c.roomCode.isEmpty ? '······' : c.roomCode,
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text('Share'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${players.length} player${players.length == 1 ? '' : 's'} in room',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: players.length,
                  itemBuilder: (context, i) {
                    final p = players[i];
                    return Card(
                      color: AppTheme.surface,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.gold.withValues(alpha: 0.15),
                          child: Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppTheme.gold, fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: p.name == c.playerName ? const Text('you', style: TextStyle(color: AppTheme.textDim, fontSize: 12)) : null,
                        trailing: p.isHost
                            ? const Tooltip(message: 'Host', child: Text('👑', style: TextStyle(fontSize: 20)))
                            : Text('🃏', style: TextStyle(fontSize: 18, color: Colors.white24)),
                      ),
                    );
                  },
                ),
              ),
              // Host-only start.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.isHost && players.length < AppConfig.minPlayers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Waiting for players… need at least ${AppConfig.minPlayers}',
                            style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                          ),
                        ),
                      if (c.isHost)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: canStart && !_starting ? _start : null,
                            icon: _starting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.ink))
                                : const Icon(Icons.play_arrow_rounded),
                            label: Text(_starting ? 'Starting…' : 'Start Game'),
                          ),
                        )
                      else
                        Text(
                          'Waiting for the host to start…',
                          style: TextStyle(color: AppTheme.textDim, fontSize: 14),
                        ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _leave,
                        child: const Text('Leave room', style: TextStyle(color: AppTheme.textDim)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    await widget.controller.startGame();
    if (!mounted) return;
    setState(() => _starting = false);
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave room?'),
        content: const Text('You will need a new invite to come back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.controller.leaveRoom();
      widget.onLeave();
    }
  }
}
