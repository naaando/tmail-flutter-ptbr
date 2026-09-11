import 'package:tmail_ui_user/features/push_notification/data/network/event_source/server_sent_event.dart';

/// Incremental parser for the `text/event-stream` wire format
/// (https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation).
///
/// It is transport agnostic: callers push decoded string chunks and receive the
/// events that are completed by the chunk. Partial lines are buffered until the
/// next chunk arrives, so it is safe to feed arbitrary chunk boundaries.
class ServerSentEventParser {
  final StringBuffer _data = StringBuffer();
  String? _event;
  String? _id;
  String _pendingLine = '';
  bool _hasData = false;

  List<ServerSentEvent> addChunk(String chunk) {
    if (chunk.isEmpty) return const [];

    _pendingLine += chunk;
    final events = <ServerSentEvent>[];

    while (true) {
      final lineBreakIndex = _pendingLine.indexOf('\n');
      if (lineBreakIndex == -1) break;

      var line = _pendingLine.substring(0, lineBreakIndex);
      _pendingLine = _pendingLine.substring(lineBreakIndex + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }

      final event = _processLine(line);
      if (event != null) {
        events.add(event);
      }
    }

    return events;
  }

  ServerSentEvent? _processLine(String line) {
    if (line.isEmpty) {
      return _dispatchEvent();
    }

    if (line.startsWith(':')) {
      // Comment line, used as a keep-alive.
      return null;
    }

    final separatorIndex = line.indexOf(':');
    final field = separatorIndex == -1 ? line : line.substring(0, separatorIndex);
    var value = separatorIndex == -1 ? '' : line.substring(separatorIndex + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    switch (field) {
      case 'event':
        _event = value;
        break;
      case 'data':
        _data.write(value);
        _data.write('\n');
        _hasData = true;
        break;
      case 'id':
        if (!value.contains('\u0000')) {
          _id = value;
        }
        break;
      case 'retry':
        break;
    }

    return null;
  }

  ServerSentEvent? _dispatchEvent() {
    if (!_hasData) {
      _event = null;
      return null;
    }

    var data = _data.toString();
    if (data.endsWith('\n')) {
      data = data.substring(0, data.length - 1);
    }

    final event = ServerSentEvent(id: _id, event: _event, data: data);

    _data.clear();
    _hasData = false;
    _event = null;

    return event;
  }
}
