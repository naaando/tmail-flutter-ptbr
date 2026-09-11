@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport_factory.dart';

void main() {
  test('creates a browser EventSource transport', () {
    expect(createEventSourceTransport(), isNotNull);
  });
}
