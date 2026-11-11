import 'package:equatable/equatable.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';

/// `SieveScript` object (RFC 9661, section 3).
class SieveScript with EquatableMixin {
  final Id id;
  final String? name;
  final String? blobId;
  final bool isActive;

  const SieveScript({
    required this.id,
    this.name,
    this.blobId,
    this.isActive = false,
  });

  factory SieveScript.fromJson(Map<String, dynamic> json) {
    return SieveScript(
      id: Id(json['id'] as String),
      name: json['name'] as String?,
      blobId: json['blobId'] as String?,
      isActive: json['isActive'] == true,
    );
  }

  @override
  List<Object?> get props => [id, name, blobId, isActive];
}
