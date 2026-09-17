import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Thin wrapper over the socket_io_client package.
///
/// The rest of the app only depends on this class (and its streams), which
/// keeps the Socket.IO dependency isolated and makes the service testable by
/// swapping in a fake.
class SocketIoService {
  io.Socket? _socket;
  final _eventController = StreamController<SocketEvent>.broadcast();
  final _connectionController = StreamController<ConnState>.broadcast();

  /// All inbound server events, surfaced as [SocketEvent]s.
  Stream<SocketEvent> get events => _eventController.stream;

  /// Connection lifecycle transitions.
  Stream<ConnState> get connectionStates => _connectionController.stream;

  /// Current connection state (last value emitted on [connectionStates]).
  ConnState state = ConnState.disconnected;

  String get socketId => _socket?.id ?? '';

  bool get isConnected => state == ConnState.connected;

  void connect({
    required String url,
    required Map<String, dynamic> auth,
    Map<String, String> transportExtraHeaders = const {},
  }) {
    disconnect();

    state = ConnState.connecting;
    _connectionController.add(state);

    // Note: reconnection attempts is left at the package default (infinite).
    final builder = io.OptionBuilder()
        .setTransports(['websocket'])
        .enableReconnection()
        .setReconnectionDelay(800)
        .setReconnectionDelayMax(6000)
        .setAuth(auth);
    if (transportExtraHeaders.isNotEmpty) {
      builder.setExtraHeaders(transportExtraHeaders);
    }
    _socket = io.io(url, builder.build());

    _socket!
      ..onConnect((_) {
        state = ConnState.connected;
        _connectionController.add(state);
      })
      ..onConnectError((err) {
        state = ConnState.error;
        _connectionController.add(state);
      })
      ..onDisconnect((_) {
        state = ConnState.disconnected;
        _connectionController.add(state);
      })
      ..onReconnectAttempt((attempt) {
        state = ConnState.reconnecting;
        _connectionController.add(state);
      })
      ..onAny((event, data) {
        _eventController.add(SocketEvent(name: event, data: data));
      });
  }

  /// Emits [event] and waits for the server ack, timing out after [timeout].
  ///
  /// Returns the ack payload (may be null when the server acks with nothing).
  /// Throws [SocketAckException] on timeout or when the server acks with an
  /// error argument (`{error: ...}` / plain error string).
  Future<dynamic> emitWithAck(String event, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 8)}) {
    final socket = _socket;
    if (socket == null || !isConnected) {
      return Future.error(const SocketAckException('Not connected', timedOut: false));
    }
    final completer = Completer<dynamic>();
    socket.emitWithAck(
      event,
      data,
      ack: (response) {
        if (completer.isCompleted) return;
        if (response is Map && (response['error'] != null || response['message'] != null && response['ok'] == false)) {
          completer.completeError(
            SocketAckException(
              response['error']?.toString() ?? response['message']?.toString() ?? 'Request failed',
              timedOut: false,
            ),
          );
        } else {
          completer.complete(response);
        }
      },
    );
    return completer.future.timeout(timeout, onTimeout: () {
      if (!completer.isCompleted) {
        completer.completeError(const SocketAckException('Server did not respond in time', timedOut: true));
      }
      throw const SocketAckException('Server did not respond in time', timedOut: true);
    });
  }

  /// Emits [event] without waiting for an ack.
  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  /// Emits a raw event without payload (some servers listen for bare events).
  void emitRaw(String event) {
    _socket?.emit(event);
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    state = ConnState.disconnected;
    _connectionController.add(state);
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _connectionController.close();
  }
}

/// Connection lifecycle states surfaced to the UI.
enum ConnState { disconnected, connecting, connected, reconnecting, error }

/// One inbound server event.
class SocketEvent {
  final String name;
  final dynamic data;
  const SocketEvent({required this.name, required this.data});

  /// First argument of the event payload, when the server sends a bare map.
  Map<String, dynamic>? get payload {
    final d = data;
    if (d is Map) return d.cast<String, dynamic>();
    if (d is List && d.isNotEmpty && d.first is Map) return (d.first as Map).cast<String, dynamic>();
    return null;
  }
}

/// Thrown when an emit-with-ack fails or times out.
class SocketAckException implements Exception {
  final String message;
  final bool timedOut;
  const SocketAckException(this.message, {required this.timedOut});

  @override
  String toString() => message;
}
