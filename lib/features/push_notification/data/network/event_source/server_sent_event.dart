
class ServerSentEvent {
  final String? id;
  final String? event;
  final String data;

  const ServerSentEvent({
    this.id,
    this.event,
    required this.data,
  });

  @override
  String toString() => 'ServerSentEvent(event: $event, id: $id, data: $data)';
}
