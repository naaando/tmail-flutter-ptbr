import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport_stub.dart'
    if (dart.library.js_interop) 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport_web.dart'
    as platform;

/// Returns the platform [EventSourceTransport] implementation.
EventSourceTransport createEventSourceTransport() =>
    platform.createPlatformEventSourceTransport();
