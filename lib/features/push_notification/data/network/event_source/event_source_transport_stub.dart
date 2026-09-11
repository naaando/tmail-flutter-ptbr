import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_connection.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport.dart';

/// Non-web fallback. Push over `text/event-stream` is a browser-only concern;
/// on mobile the FCM/WebSocket paths are used instead.
EventSourceTransport createPlatformEventSourceTransport() =>
    const _UnsupportedEventSourceTransport();

class _UnsupportedEventSourceTransport implements EventSourceTransport {
  const _UnsupportedEventSourceTransport();

  @override
  EventSourceConnection connect(Uri url, {required Map<String, String> headers}) =>
      const _UnsupportedEventSourceConnection();
}

class _UnsupportedEventSourceConnection implements EventSourceConnection {
  const _UnsupportedEventSourceConnection();

  @override
  Stream<String> get chunks => const Stream<String>.empty();

  @override
  Future<void> close() async {}
}
