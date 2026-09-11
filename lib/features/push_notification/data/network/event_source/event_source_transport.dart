import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_connection.dart';

/// Opens `text/event-stream` connections used by the push notification layer.
///
/// The production implementation is selected at compile time (browser fetch on
/// web, a no-op stub elsewhere) so that mobile builds never pull in browser
/// APIs.
abstract class EventSourceTransport {
  EventSourceConnection connect(Uri url, {required Map<String, String> headers});
}
