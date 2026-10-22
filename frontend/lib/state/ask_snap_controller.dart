import 'package:flutter/foundation.dart';
import '../data/backend_api.dart';
import '../models/ask_snap_reply.dart';

/// Un échange fige le contexte utilisé pour rendre une nouvelle tentative fidèle.
class AskSnapExchange {
  AskSnapExchange(this.question, this.history, this.currency);
  final String question;
  final List<Map<String, dynamic>> history;
  final String? currency;
  AskSnapReply? _reply;
  String? _error;
  AskSnapReply? get reply => _reply;
  String? get error => _error;
}

/// État métier éphémère du chat, indépendant de BuildContext et de la navigation.
class AskSnapController extends ChangeNotifier {
  AskSnapController(this.api);
  final BackendApi? api;
  final _exchanges = <AskSnapExchange>[];
  List<AskSnapExchange> get exchanges => List.unmodifiable(_exchanges);
  bool _busy = false, _disposed = false;
  bool get busy => _busy;
  String? _currency;
  String? get currency => _currency;

  void selectCurrency(String? value) {
    if (_busy || _disposed) return;
    _currency = value;
    notifyListeners();
  }

  void clear() {
    if (_busy || _disposed) return;
    _exchanges.clear();
    notifyListeners();
  }

  Future<void> send(String question, {bool retry = false}) async {
    if (_busy || _disposed || question.trim().isEmpty || api == null) return;
    if (retry && (_exchanges.isEmpty || _exchanges.last.error == null)) return;
    final history = <Map<String, dynamic>>[];
    for (final exchange in _exchanges) {
      final reply = exchange.reply;
      if (reply == null) continue;
      history.add({'role': 'user', 'content': exchange.question});
      history.add({
        'role': 'assistant',
        'content': reply.answer.length > 2000
            ? reply.answer.substring(0, 2000)
            : reply.answer,
      });
    }
    final exchange = retry
        ? _exchanges.last
        : AskSnapExchange(
            question.trim(),
            List.unmodifiable(
              history.skip(history.length > 6 ? history.length - 6 : 0),
            ),
            _currency,
          );
    _busy = true;
    exchange._error = null;
    if (!retry) {
      _exchanges.add(exchange);
      if (_exchanges.length > 20) _exchanges.removeAt(0);
    }
    notifyListeners();
    try {
      final reply = await api!.askSnap(
        exchange.question,
        currency: exchange.currency,
        history: exchange.history,
      );
      if (!_disposed) exchange._reply = reply;
    } catch (error) {
      if (!_disposed) {
        exchange._error = error is ApiException
            ? error.message
            : 'Could not load your answer. Please retry.';
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _exchanges.clear();
    super.dispose();
  }
}
