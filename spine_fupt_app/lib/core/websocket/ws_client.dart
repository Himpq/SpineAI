import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

typedef WsMessageHandler = void Function(Map<String, dynamic> message);

class WsClient {
  WebSocketChannel? _channel;
  String? _url;
  String? _kind;
  String? _name;
  int? _userId;
  bool _shouldReconnect = true;
  Timer? _heartbeatTimer;
  final Set<String> _subscribedChannels = {};
  final Map<String, Set<WsMessageHandler>> _handlers = {};
  final List<WsMessageHandler> _globalHandlers = [];
  bool _connected = false;
  int _reconnectAttempts = 0;
  static const _maxReconnectDelay = 30000; // 30s max
  /// Callback fired whenever the connection state changes.
  void Function(bool connected)? onConnectionChanged;

  bool get isConnected => _connected;

  void _setConnected(bool value) {
    if (_connected != value) {
      _connected = value;
      onConnectionChanged?.call(value);
    }
  }

  void connect(String host, {required String kind, required String name, int? userId}) {
    _kind = kind;
    _name = name;
    _userId = userId;
    final scheme = host.startsWith('https') ? 'wss' : 'ws';
    final cleanHost = host.replaceAll(RegExp(r'^https?://'), '');
    _url = '$scheme://$cleanHost/ws';
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _doConnect();
  }

  void _doConnect() {
    if (_url == null) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url!));
      _setConnected(true);

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            _handleMessage(msg);
          } catch (e) {
            debugPrint('[WS] Parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('[WS] Error: $error');
          _setConnected(false);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[WS] Connection closed');
          _setConnected(false);
          _scheduleReconnect();
        },
      );

      // Send hello
      _send({
        'type': 'hello',
        'kind': _kind,
        'name': _name,
        if (_userId != null) 'id': _userId,
      });

      // Resubscribe channels
      if (_subscribedChannels.isNotEmpty) {
        _send({
          'type': 'subscribe',
          'channels': _subscribedChannels.toList(),
        });
      }

      // Start heartbeat
      _heartbeatTimer?.cancel();
      _reconnectAttempts = 0;
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _send({'type': 'ping'});
      });
    } catch (e) {
      debugPrint('[WS] Connect error: $e');
      _setConnected(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    if (_shouldReconnect) {
      _reconnectAttempts++;
      // Exponential backoff: 1.2s, 2.4s, 4.8s, ... up to 30s max
      final delay = (1200 * (1 << (_reconnectAttempts - 1).clamp(0, 5))).clamp(1200, _maxReconnectDelay);
      Future.delayed(Duration(milliseconds: delay), () {
        if (_shouldReconnect) {
          debugPrint('[WS] Reconnecting (attempt $_reconnectAttempts, delay ${delay}ms)...');
          _doConnect();
        }
      });
    }
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _connected) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        debugPrint('[WS] Send error: $e');
      }
    }
  }

  void subscribe(String channel) {
    _subscribedChannels.add(channel);
    _send({'type': 'subscribe', 'channel': channel});
  }

  void unsubscribe(String channel) {
    _subscribedChannels.remove(channel);
    _send({'type': 'unsubscribe', 'channel': channel});
    _handlers.remove(channel);
  }

  void on(String type, WsMessageHandler handler) {
    _handlers.putIfAbsent(type, () => {});
    _handlers[type]!.add(handler);
  }

  void off(String type, WsMessageHandler handler) {
    _handlers[type]?.remove(handler);
  }

  void onAny(WsMessageHandler handler) {
    _globalHandlers.add(handler);
  }

  void offAny(WsMessageHandler handler) {
    _globalHandlers.remove(handler);
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null) return;

    // Global handlers
    for (final h in _globalHandlers) {
      h(msg);
    }

    // Type-specific handlers
    if (_handlers.containsKey(type)) {
      for (final h in _handlers[type]!) {
        h(msg);
      }
    }
  }

  void sendFieldFocus(String channel, Map<String, dynamic> payload) {
    _send({'type': 'field_focus', 'channel': channel, 'payload': payload});
  }

  void sendFieldChange(String channel, Map<String, dynamic> payload) {
    _send({'type': 'field_change', 'channel': channel, 'payload': payload});
  }

  void sendTyping(String channel, Map<String, dynamic> payload) {
    _send({'type': 'typing', 'channel': channel, 'payload': payload});
  }

  void disconnect() {
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _setConnected(false);
    _channel?.sink.close();
    _channel = null;
    _subscribedChannels.clear();
    _handlers.clear();
    _globalHandlers.clear();
  }
}
