import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/server_sent_event_parser.dart';

void main() {
  group('ServerSentEventParser', () {
    test('parses a single event with a name and data', () {
      final parser = ServerSentEventParser();

      final events = parser.addChunk(
        'event: state\n'
        'data: {"a":1}\n'
        '\n',
      );

      expect(events, hasLength(1));
      expect(events.single.event, 'state');
      expect(events.single.data, '{"a":1}');
    });

    test('buffers a partial line across chunks', () {
      final parser = ServerSentEventParser();

      expect(parser.addChunk('event: sta'), isEmpty);
      expect(parser.addChunk('te\ndata: payload\n\n'), hasLength(1));
    });

    test('joins multiple data lines with a newline', () {
      final parser = ServerSentEventParser();

      final events = parser.addChunk(
        'event: state\n'
        'data: line1\n'
        'data: line2\n'
        '\n',
      );

      expect(events.single.data, 'line1\nline2');
    });

    test('dispatches multiple events from a single chunk', () {
      final parser = ServerSentEventParser();

      final events = parser.addChunk(
        'event: state\ndata: one\n\n'
        'event: state\ndata: two\n\n',
      );

      expect(events.map((event) => event.data), ['one', 'two']);
    });

    test('ignores comment lines used as keep-alive', () {
      final parser = ServerSentEventParser();

      final events = parser.addChunk(
        ': keep-alive\n'
        'event: ping\n'
        'data: {"interval":30}\n'
        '\n',
      );

      expect(events, hasLength(1));
      expect(events.single.event, 'ping');
    });

    test('strips a single leading space from the field value', () {
      final parser = ServerSentEventParser();

      final events = parser.addChunk('event: state\ndata:{"a":1}\n\n');

      expect(events.single.data, '{"a":1}');
    });

    test('handles CRLF line endings', () {
      final parser = ServerSentEventParser();

      final events = parser.addChunk('event: state\r\ndata: {"a":1}\r\n\r\n');

      expect(events, hasLength(1));
      expect(events.single.event, 'state');
      expect(events.single.data, '{"a":1}');
    });

    test('does not dispatch an event without data', () {
      final parser = ServerSentEventParser();

      final events = parser.addChunk('event: state\n\n');

      expect(events, isEmpty);
    });
  });
}
