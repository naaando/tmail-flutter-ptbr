import 'dart:async';
import 'dart:js_interop';

import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_connection.dart';
import 'package:tmail_ui_user/features/push_notification/data/network/event_source/event_source_transport.dart';
import 'package:web/web.dart' as web;

/// Browser implementation of [EventSourceTransport] built on `fetch` with a
/// streamed response body.
///
/// The native `EventSource` API cannot attach an `Authorization` header, which
/// is exactly why the WebSocket path needs a ticket handshake on Linagora
/// servers. `fetch` can send that header and expose the response as a
/// `ReadableStream`, so Stalwart's core JMAP `eventSourceUrl` can be consumed
/// directly.
EventSourceTransport createPlatformEventSourceTransport() =>
    const _WebEventSourceTransport();

class _WebEventSourceTransport implements EventSourceTransport {
  const _WebEventSourceTransport();

  @override
  EventSourceConnection connect(Uri url, {required Map<String, String> headers}) {
    final abortController = web.AbortController();
    final chunks = StreamController<String>();
    var closed = false;

    Future<void> readResponse() async {
      try {
        final requestHeaders = web.Headers();
        headers.forEach((key, value) => requestHeaders.set(key, value));

        final response = await web.window
            .fetch(
              url.toString().toJS,
              web.RequestInit(
                method: 'GET',
                headers: requestHeaders,
                signal: abortController.signal,
              ),
            )
            .toDart;

        if (!response.ok) {
          throw Exception(
            'EventSource request failed with status ${response.status}',
          );
        }

        final body = response.body;
        if (body == null) return;

        final reader = web.ReadableStreamDefaultReader(body);
        final decoder = web.TextDecoder();

        while (!closed) {
          final result = await reader.read().toDart;
          if (result.done) break;

          final value = result.value;
          if (value == null) continue;

          final chunk = decoder.decode(
            value as JSUint8Array,
            web.TextDecodeOptions(stream: true),
          );
          if (chunk.isNotEmpty) {
            chunks.add(chunk);
          }
        }
      } catch (error, stackTrace) {
        if (!closed) {
          chunks.addError(error, stackTrace);
        }
      } finally {
        if (!closed && !chunks.isClosed) {
          await chunks.close();
        }
      }
    }

    unawaited(readResponse());

    return _WebEventSourceConnection(
      chunks: chunks.stream,
      onClose: () async {
        if (closed) return;
        closed = true;
        abortController.abort();
        if (!chunks.isClosed) {
          await chunks.close();
        }
      },
    );
  }
}

class _WebEventSourceConnection implements EventSourceConnection {
  final Stream<String> _chunks;
  final Future<void> Function() _onClose;
  bool _isClosed = false;

  _WebEventSourceConnection({
    required Stream<String> chunks,
    required Future<void> Function() onClose,
  })  : _chunks = chunks,
        _onClose = onClose;

  @override
  Stream<String> get chunks => _chunks;

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _onClose();
  }
}
