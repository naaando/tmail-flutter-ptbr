import 'package:jmap_dart_client/jmap/core/capability/capability_identifier.dart';

/// JMAP for Sieve (RFC 9661).
final capabilitySieve =
    CapabilityIdentifier(Uri.parse('urn:ietf:params:jmap:sieve'));

/// JMAP Blob management (RFC 9404). Used to upload and read script contents
/// inside JMAP requests, without touching the upload/download endpoints.
final capabilityBlob =
    CapabilityIdentifier(Uri.parse('urn:ietf:params:jmap:blob'));
