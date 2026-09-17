import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../controllers/game_controller.dart';
import '../models/game_events.dart';
import '../widgets/connection_badge.dart';
import '../widgets/felt_background.dart';

/// Final standings after game_finished / leaderboard events.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({
    super.key,
    required this.controller,
    required this.onExit,
    required this.onRestarted,
  });

  final GameController controller;
  final VoidCallback onExit;
  final VoidCallback onRestarted;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
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
    // Server restarted the game (host pressed Play Again): jump back to table.
    if (widget.controller.leaderboard == null && widget.controller.state.self?.hand.isNotEmpty == true) {
      widget.onRestarted();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final entries = c.leaderboard ?? const <LeaderboardEntry>[];
    final top = entries.take(3).toList();
    final rest = entries.length > 3 ? entries.sublist(3) : <LeaderboardEntry>[];

    return FeltBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Leaderboard'),
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Center(child: Text('🏆', style: TextStyle(fontSize: 54))),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Waiting for final scores…', style: TextStyle(color: AppTheme.textDim)),
                        ),
                      )
                    else ...[
                      // Top-3 podium.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < top.length; i++) _PodiumTile(entry: top[i], place: i + 1),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Remaining rows.
                      for (final e in rest)
                        Card(
                          color: AppTheme.surface,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Text('#${e.rank}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textDim)),
                            title: Text(e.name),
                            trailing: Text('${e.score}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gold)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.isHost)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: c.busy ? null : () async {
                          await c.playAgain();
                        },
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Play Again'),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text('Waiting for the host to start a new game…',
                          style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await c.leaveRoom();
                      widget.onExit();
                    },
                    child: const Text('Exit to Home'),
                  ),
                ],
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PodiumTile extends StatelessWidget {
  const _PodiumTile({required this.entry, required this.place});

  final LeaderboardEntry entry;
  final int place;

  @override
  Widget build(BuildContext context) {
    const medals = ['🥇', '🥈', '🥉'];
    final sizes = [92.0, 78.0, 78.0];
    final idx = place - 1;
    final h = sizes[idx];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(medals[idx], style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 6),
          Container(
            width: h + 30,
            height: h,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: place == 1 ? AppTheme.gold.withValues(alpha: 0.16) : AppTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border.all(color: place == 1 ? AppTheme.gold : AppTheme.feltEdge, width: place == 1 ? 1.6 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('${entry.score} pts',
                    style: const TextStyle(color: AppTheme.gold, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
