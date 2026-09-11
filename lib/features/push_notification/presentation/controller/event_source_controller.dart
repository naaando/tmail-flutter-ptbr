import 'dart:async';
import 'dart:convert';

import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:core/utils/app_logger.dart';
import 'package:core/utils/platform_info.dart';
import 'package:flutter/foundation.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:jmap_dart_client/jmap/push/state_change.dart';
import 'package:model/extensions/account_id_extensions.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_connection.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport_factory.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/server_sent_event.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/server_sent_event_parser.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/controller/push_base_controller.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/extensions/state_change_extension.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/listener/email_change_listener.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/listener/label_change_listener.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/listener/mailbox_change_listener.dart';

/// Browser push over the core JMAP `eventSourceUrl` (`text/event-stream`).
///
/// This is used when the server advertises a JMAP WebSocket endpoint but not
/// the Linagora ticket capability the WebSocket controller requires to
/// authenticate from a browser. The state changes received here are dispatched
/// through the exact same listeners as the WebSocket path.
class EventSourceController extends PushBaseController {
  EventSourceController._internal();

  static final EventSourceController _instance = EventSourceController._internal();

  static EventSourceController get instance => _instance;

  @visibleForTesting
  static EventSourceTransport? transportOverride;

  @visibleForTesting
  void Function(StateChange stateChange)? stateChangeListenerForTesting;

  static const List<String> _mailTypes = ['Email', 'Mailbox'];
  static const List<String> _labelTypes = ['Email', 'Mailbox', 'Label'];
  static const String _stateEventName = 'state';
  static const Duration _reconnectBaseDelay = Duration(seconds: 1);
  static const Duration _reconnectMaxDelay = Duration(seconds: 30);
  static const int _maxReconnectShift = 5;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isLabelAvailable = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  EventSourceConnection? _connection;
  StreamSubscription<String>? _chunksSubscription;
  Timer? _reconnectTimer;
  ServerSentEventParser? _parser;
  String? Function()? _authorizationHeaderProvider;

  EventSourceTransport get _transport =>
      transportOverride ?? createEventSourceTransport();

  @override
  void initialize({
    AccountId? accountId,
    Session? session,
    bool isLabelAvailable = false,
    String? Function()? authorizationHeaderProvider,
  }) {
    log('EventSourceController::initialize: accountId = ${accountId?.asString}, isLabelAvailable = $isLabelAvailable');
    super.initialize(accountId: accountId, session: session);
    _disposed = false;
    _reset();
    _isLabelAvailable = isLabelAvailable;
    _authorizationHeaderProvider = authorizationHeaderProvider;
    _connect();
  }

  @override
  void onClose() {
    _disposed = true;
    _reset();
    super.onClose();
  }

  void _reset() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _chunksSubscription?.cancel();
    _chunksSubscription = null;
    _connection?.close();
    _connection = null;
    _parser = null;
    _reconnectAttempt = 0;
    _isConnected = false;
  }

  void _connect() {
    if (_disposed || !PlatformInfo.isWeb) return;
    final currentSession = session;
    final currentAccountId = accountId;
    if (currentSession == null || currentAccountId == null) return;
    if (_connection != null) return;

    final url = _buildEventSourceUrl(currentSession);
    if (url == null) {
      logWarning('EventSourceController::_connect: eventSourceUrl is unavailable');
      return;
    }

    _parser = ServerSentEventParser();
    try {
      _connection = _transport.connect(url, headers: _buildHeaders());
      _chunksSubscription = _connection!.chunks.listen(
        _handleChunk,
        onError: (error, stackTrace) {
          logWarning('EventSourceController::_connect:onError: $error');
          _handleDisconnected();
        },
        onDone: () {
          log('EventSourceController::_connect:onDone');
          _handleDisconnected();
        },
        cancelOnError: true,
      );
    } catch (error) {
      logWarning('EventSourceController::_connect:exception: $error');
      _handleDisconnected();
    }
  }

  Uri? _buildEventSourceUrl(Session currentSession) {
    final eventSourceUrl = currentSession.eventSourceUrl;
    if (eventSourceUrl.toString().trim().isEmpty) return null;

    final types = _isLabelAvailable ? _labelTypes : _mailTypes;
    final resolvedParameters = <String, String>{};

    // The server advertises a template such as
    // `...?types={types}&closeafter={closeafter}&ping={ping}`. Uri.parse
    // percent-encodes the braces, so the substitution has to run on the decoded
    // query values rather than on the raw string.
    eventSourceUrl.queryParameters.forEach((key, value) {
      resolvedParameters[key] = value
          .replaceAll('{types}', types.join(','))
          .replaceAll('{closeafter}', 'no')
          .replaceAll('{ping}', '30');
    });

    if ((resolvedParameters['types'] ?? '').isEmpty) {
      resolvedParameters['types'] = types.join(',');
    }

    try {
      return eventSourceUrl.replace(queryParameters: resolvedParameters);
    } catch (error) {
      logWarning('EventSourceController::_buildEventSourceUrl: $error');
      return null;
    }
  }

  Map<String, String> _buildHeaders() {
    final authorizationHeader = _authorizationHeaderProvider?.call();
    if (authorizationHeader == null || authorizationHeader.isEmpty) {
      return const {};
    }
    return {'Authorization': authorizationHeader};
  }

  void _handleChunk(String chunk) {
    _markConnected();
    final parser = _parser;
    if (parser == null) return;
    for (final event in parser.addChunk(chunk)) {
      _handleServerSentEvent(event);
    }
  }

  void _handleServerSentEvent(ServerSentEvent event) {
    if (event.event != _stateEventName) return;
    try {
      final decoded = jsonDecode(event.data);
      if (decoded is! Map<String, dynamic>) return;
      _handleStateChange(StateChange.fromJson(decoded));
    } catch (error, stackTrace) {
      logWarning('EventSourceController::_handleServerSentEvent: $error');
      logError(
        'EventSourceController::_handleServerSentEvent:Error',
        exception: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleStateChange(StateChange stateChange) {
    final listener = stateChangeListenerForTesting;
    if (listener != null) {
      listener(stateChange);
      return;
    }

    final currentAccountId = accountId;
    final currentSession = session;
    if (currentAccountId == null || currentSession == null) return;

    final mapTypeState = stateChange.getMapTypeState(currentAccountId);
    mappingTypeStateToAction(
      mapTypeState,
      currentAccountId,
      currentSession.username,
      emailChangeListener: EmailChangeListener.instance,
      mailboxChangeListener: MailboxChangeListener.instance,
      labelChangeListener: LabelChangeListener.instance,
      session: currentSession,
    );
  }

  void _markConnected() {
    _reconnectAttempt = 0;
    if (_isConnected) return;
    _isConnected = true;
    log('EventSourceController::_markConnected');
  }

  void _handleDisconnected() {
    _isConnected = false;
    _chunksSubscription?.cancel();
    _chunksSubscription = null;
    _connection?.close();
    _connection = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !PlatformInfo.isWeb) return;
    if (session == null || accountId == null) return;

    _reconnectTimer?.cancel();
    final delay = _nextReconnectDelay();
    log('EventSourceController::_scheduleReconnect: delay = $delay, attempt = $_reconnectAttempt');
    _reconnectTimer = Timer(delay, _connect);
  }

  Duration _nextReconnectDelay() {
    final multiplier = 1 << _reconnectAttempt.clamp(0, _maxReconnectShift);
    final seconds = _reconnectBaseDelay.inSeconds * multiplier;
    final cappedSeconds = seconds.clamp(
      _reconnectBaseDelay.inSeconds,
      _reconnectMaxDelay.inSeconds,
    );

    if (_reconnectAttempt < _maxReconnectShift) {
      _reconnectAttempt++;
    }

    return Duration(seconds: cappedSeconds);
  }

  @override
  void handleFailureViewState(Failure failure) {
    logWarning('EventSourceController::handleFailureViewState(): $failure');
  }

  @override
  void handleSuccessViewState(Success success) {
    log('EventSourceController::handleSuccessViewState(): $success');
  }
}
