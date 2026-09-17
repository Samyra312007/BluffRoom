import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../core/session_store.dart';
import '../controllers/game_controller.dart';
import '../services/socket_io_service.dart';
import '../widgets/connection_badge.dart';
import '../widgets/felt_background.dart';

/// Entry screen: create or join a room.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.session,
    required this.onRoomReady,
  });

  final GameController controller;
  final SessionStore session;
  final void Function() onRoomReady;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  int _maxPlayers = AppConfig.maxPlayers;
  bool _createMode = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.session.playerName ?? '';
    _codeCtrl.text = widget.session.lastRoomCode ?? '';
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    if (widget.controller.kickedMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.kickedMessage!)),
      );
      widget.controller.kickedMessage = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext appContext) {
    final controller = widget.controller;

    return FeltBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(AppConfig.appName),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: ConnectionBadge(state: controller.connState)),
            ),
          ],
        ),
        body: SafeArea(
          child:          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Logo row
                    Text('🃏', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 56)),
                    const SizedBox(height: 4),
                    const Text(
                      'BLUFFROOM',
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const Text(
                      'bluff · challenge · survive',
                      style: TextStyle(color: AppTheme.textDim, fontSize: 13, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 18),
                    if (!AppConfig.hasExplicitServerUrl) ...[
                      const _ServerBanner(),
                      const SizedBox(height: 18),
                    ],
                    // Mode switch
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Create Room'), icon: Icon(Icons.add_circle_outline)),
                        ButtonSegment(value: false, label: Text('Join Room'), icon: Icon(Icons.login)),
                      ],
                      selected: {_createMode},
                      onSelectionChanged: (s) => setState(() => _createMode = s.first),
                      style: SegmentedButton.styleFrom(
                        backgroundColor: AppTheme.surface,
                        foregroundColor: AppTheme.textDim,
                        selectedForegroundColor: AppTheme.ink,
                        selectedBackgroundColor: AppTheme.gold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameCtrl,
                      maxLength: 16,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        counterText: '',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) {
                        final name = v?.trim() ?? '';
                        if (name.isEmpty) return 'Enter a name';
                        if (name.length < 2) return 'At least 2 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _createMode
                          ? _PlayerCountSelector(
                              key: const ValueKey('players'),
                              value: _maxPlayers,
                              onChanged: (v) => setState(() => _maxPlayers = v),
                            )
                          : TextFormField(
                              key: const ValueKey('code'),
                              controller: _codeCtrl,
                              maxLength: 8,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Room code',
                                counterText: '',
                                prefixIcon: Icon(Icons.meeting_room_outlined),
                              ),
                              validator: (v) {
                                final code = v?.trim().toUpperCase() ?? '';
                                if (code.isEmpty) return 'Enter the room code';
                                if (code.length < 4) return 'Codes are at least 4 characters';
                                return null;
                              },
                            ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting || controller.connState != ConnState.connected ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.gold,
                          disabledBackgroundColor: AppTheme.surfaceHigh,
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.ink),
                              )
                            : Text(_createMode ? 'Create Room' : 'Join Room'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final controller = widget.controller;
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();

    final ok = _createMode
        ? await controller.createRoom(name, _maxPlayers)
        : await controller.joinRoom(name, code);

    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      widget.onRoomReady();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach the room — check the server address and try again.')),
      );
    }
  }
}

class _PlayerCountSelector extends StatelessWidget {
  const _PlayerCountSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Players: $value', style: const TextStyle(color: AppTheme.cream, fontWeight: FontWeight.w600)),
        Slider(
          value: value.toDouble(),
          min: AppConfig.minPlayers.toDouble(),
          max: AppConfig.maxPlayers.toDouble(),
          divisions: AppConfig.maxPlayers - AppConfig.minPlayers,
          label: '$value',
          activeColor: AppTheme.gold,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

class _ServerBanner extends StatelessWidget {
  const _ServerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: AppTheme.gold, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No SERVER_URL configured — using the local dev fallback.\nSet it with --dart-define=SERVER_URL=… when building (see README).',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
