/// A live connection to a `text/event-stream` endpoint.
///
/// [chunks] emits decoded string chunks as they arrive from the network. The
/// consumer is expected to feed them into a
/// [ServerSentEventParser] to obtain complete events.
abstract class EventSourceConnection {
  Stream<String> get chunks;

  Future<void> close();
}
