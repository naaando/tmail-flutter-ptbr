import 'dart:async';

import 'package:core/utils/platform_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/push/state_change.dart';
import 'package:model/extensions/account_id_extensions.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_connection.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/controller/event_source_controller.dart';

import '../../../../fixtures/account_fixtures.dart';
import '../../../../fixtures/session_fixtures.dart';

class _FakeEventSourceConnection implements EventSourceConnection {
  final StreamController<String> controller = StreamController<String>();
  final Uri url;
  final Map<String, String> headers;

  _FakeEventSourceConnection({required this.url, required this.headers});

  void emit(String chunk) {
    if (!controller.isClosed) {
      controller.add(chunk);
    }
  }

  Future<void> endStream() async {
    if (!controller.isClosed) {
      await controller.close();
    }
  }

  @override
  Stream<String> get chunks => controller.stream;

  @override
  Future<void> close() async {
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

class _FakeEventSourceTransport implements EventSourceTransport {
  final List<_FakeEventSourceConnection> connections = [];

  @override
  EventSourceConnection connect(Uri url, {required Map<String, String> headers}) {
    final connection = _FakeEventSourceConnection(url: url, headers: headers);
    connections.add(connection);
    return connection;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEventSourceTransport transport;
  final controller = EventSourceController.instance;

  setUp(() {
    PlatformInfo.isTestingForWeb = true;
    transport = _FakeEventSourceTransport();
    EventSourceController.transportOverride = transport;
  });

  tearDown(() {
    controller.onClose();
    controller.stateChangeListenerForTesting = null;
    EventSourceController.transportOverride = null;
    PlatformInfo.isTestingForWeb = false;
  });

  void initializeController({
    void Function(StateChange stateChange)? onStateChange,
  }) {
    controller.stateChangeListenerForTesting = onStateChange;
    controller.initialize(
      accountId: AccountFixtures.aliceAccountId,
      session: SessionFixtures.aliceSession,
      authorizationHeaderProvider: () => 'Basic dGVzdA==',
    );
  }

  test('opens the JMAP event source with the required query parameters', () async {
    initializeController();

    expect(transport.connections, hasLength(1));
    final connection = transport.connections.single;
    expect(connection.url.queryParameters['types'], 'Email,Mailbox');
    expect(connection.url.queryParameters['ping'], '30');
    expect(connection.headers['Authorization'], 'Basic dGVzdA==');
  });

  test('dispatches a StateChange parsed from a Stalwart state event', () async {
    StateChange? received;
    initializeController(onStateChange: (change) => received = change);

    transport.connections.single.emit(
      'event: state\n'
      'data: {"@type":"StateChange","changed":{"${AccountFixtures.aliceAccountId.asString}":{"Email":"42"}}}\n\n',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.isConnected, isTrue);
    expect(received, isNotNull);
    expect(
      received!.changed[AccountFixtures.aliceAccountId]?.typeState['Email'],
      '42',
    );
  });

  test('ignores ping events', () async {
    StateChange? received;
    initializeController(onStateChange: (change) => received = change);

    transport.connections.single.emit('event: ping\ndata: {"interval":30}\n\n');
    await Future<void>.delayed(Duration.zero);

    expect(received, isNull);
  });

  test('reconnects after the stream is closed', () async {
    initializeController();
    await transport.connections.single.endStream();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isConnected, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(transport.connections.length, greaterThanOrEqualTo(2));
  });

  test('does not reconnect after onClose', () async {
    initializeController();
    await transport.connections.single.endStream();
    await Future<void>.delayed(Duration.zero);

    controller.onClose();
    final connectionCountAfterClose = transport.connections.length;

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(transport.connections.length, connectionCountAfterClose);
    expect(controller.isConnected, isFalse);
  });
}
