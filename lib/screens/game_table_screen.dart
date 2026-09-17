import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../controllers/game_controller.dart';
import '../widgets/connection_badge.dart';
import '../widgets/felt_background.dart';
import '../widgets/playing_card_view.dart';
import '../widgets/turn_timer_ring.dart';

/// Main table during a match.
class GameTableScreen extends StatefulWidget {
  const GameTableScreen({
    super.key,
    required this.controller,
    required this.onLeaderboard,
    required this.onExit,
  });

  final GameController controller;
  final VoidCallback onLeaderboard;
  final VoidCallback onExit;

  @override
  State<GameTableScreen> createState() => _GameTableScreenState();
}

class _GameTableScreenState extends State<GameTableScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    WidgetsBinding.instance.removeObserver(_lifecycle);
    super.dispose();
  }

  late final _lifecycle = _AppLifecycle(this);

  void _onController() {
    if (!mounted) return;
    final c = widget.controller;
    if (c.leaderboard != null) {
      widget.onLeaderboard();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final g = c.state;
    final me = g.self;
    final turn = g.turn;
    final myTurn = c.isMyTurn;

    return FeltBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            children: [
              Text(
                g.currentRank == null ? 'BluffRoom' : 'Rank to play: ${_rankLabel(g.currentRank!)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                'Room ${c.roomCode}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim, fontWeight: FontWeight.w400),
              ),
            ],
          ),
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
              // Turn strip: whose turn + timer.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: myTurn ? AppTheme.gold.withValues(alpha: 0.15) : AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: myTurn ? AppTheme.gold : AppTheme.feltEdge,
                            width: myTurn ? 1.6 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(myTurn ? Icons.flash_on_rounded : Icons.hourglass_top_rounded,
                                size: 20, color: myTurn ? AppTheme.gold : AppTheme.textDim),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                turn == null
                                    ? 'Dealing…'
                                    : myTurn
                                        ? 'Your turn!'
                                        : '${turn.playerName} is thinking…',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: myTurn ? AppTheme.gold : AppTheme.cream,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (c.secondsLeft > 0) ...[
                      const SizedBox(width: 10),
                      TurnTimerRing(secondsLeft: c.secondsLeft, totalSeconds: AppConfig.turnSeconds),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Opponents row.
              SizedBox(
                height: 92,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: c.opponents.length,
                  itemBuilder: (context, i) {
                    final o = c.opponents[i];
                    final isTurn = turn != null && (o.id == turn.playerId || o.name == turn.playerName);
                    return Container(
                      width: 108,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isTurn ? AppTheme.gold.withValues(alpha: 0.14) : AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isTurn ? AppTheme.gold : AppTheme.feltEdge,
                          width: isTurn ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.style_rounded, size: 13, color: AppTheme.textDim),
                              const SizedBox(width: 4),
                              Text('${o.cardCount} cards', style: const TextStyle(fontSize: 12, color: AppTheme.textDim)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // Pile.
              Expanded(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PileStackView(count: g.pileCount),
                      const SizedBox(height: 6),
                      Text(
                        '${g.pileCount} card${g.pileCount == 1 ? '' : 's'} in the pile',
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),

              // Hand.
              Container(
                height: 150,
                color: Colors.black26,
                child: me == null || me.hand.isEmpty
                    ? const Center(child: Text('Waiting for cards…', style: TextStyle(color: AppTheme.textDim)))
                    : Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
                              itemCount: me.hand.length,
                              itemBuilder: (context, i) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: PlayingCardView(
                                    card: me.hand[i],
                                    selected: c.selectedCardIndexes.contains(i),
                                    onTap: myTurn ? () => c.toggleCard(i) : null,
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: c.canPlay ? c.playSelected : null,
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: Text(
                                      c.selectedCardIndexes.isEmpty
                                          ? 'Select 1–${AppConfig.maxCardsPerPlay} cards'
                                          : 'Play ${c.selectedCardIndexes.length} as ${_rankLabel(g.currentRank ?? '')}',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  onPressed: c.canChallenge ? c.challenge : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.danger,
                                    foregroundColor: AppTheme.cream,
                                  ),
                                  icon: const Icon(Icons.gavel_rounded),
                                  label: const Text('Bluff!'),
                                ),
                              ],
                            ),
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

  static String _rankLabel(String rank) => switch (rank) {
        'T' => '10',
        '' => '?',
        _ => rank,
      };
}

class _AppLifecycle with WidgetsBindingObserver {
  _AppLifecycle(this._state);

  final _GameTableScreenState _state;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding stops local haptics/timer churn; the socket package keeps
    // trying to reconnect automatically and the controller syncs the timer
    // from the next authoritative turn event on return.
    if (state == AppLifecycleState.resumed) {
      _state.widget.controller.service.requestState();
    }
  }
}
