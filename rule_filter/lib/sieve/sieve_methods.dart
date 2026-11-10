import 'package:jmap_dart_client/http/converter/account_id_converter.dart';
import 'package:jmap_dart_client/http/converter/state_nullable_converter.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/capability/capability_identifier.dart';
import 'package:jmap_dart_client/jmap/core/error/set_error.dart';
import 'package:jmap_dart_client/jmap/core/method/method.dart';
import 'package:jmap_dart_client/jmap/core/method/method_response.dart';
import 'package:jmap_dart_client/jmap/core/request/request_invocation.dart';
import 'package:jmap_dart_client/jmap/core/state.dart';
import 'package:rule_filter/sieve/capability_sieve.dart';
import 'package:rule_filter/sieve/sieve_script.dart';

Map<String, dynamic> _accountJson(AccountId accountId) => <String, dynamic>{
      'accountId': const AccountIdConverter().toJson(accountId),
    };

/// `SieveScript/get` (RFC 9661, section 3.1).
class GetSieveScriptMethod extends MethodRequiringAccountId {
  final List<String>? ids;
  final List<String>? properties;

  GetSieveScriptMethod(super.accountId, {this.ids, this.properties});

  @override
  MethodName get methodName => MethodName('SieveScript/get');

  @override
  Set<CapabilityIdentifier> get requiredCapabilities => {
        CapabilityIdentifier.jmapCore,
        capabilitySieve,
      };

  @override
  Map<String, dynamic> toJson() => _accountJson(accountId)
    ..addAll({
      if (ids != null) 'ids': ids,
      if (properties != null) 'properties': properties,
    });

  @override
  List<Object?> get props => [accountId, ids, properties];
}

class GetSieveScriptResponse extends MethodResponse {
  final State? state;
  final List<SieveScript> list;

  GetSieveScriptResponse({this.state, required this.list});

  static GetSieveScriptResponse deserialize(Map<String, dynamic> json) {
    return GetSieveScriptResponse(
      state: const StateNullableConverter().fromJson(json['state'] as String?),
      list: (json['list'] as List<dynamic>? ?? const [])
          .map((e) => SieveScript.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [state, list];
}

/// `SieveScript/set` (RFC 9661, section 3.2). Only the arguments needed by
/// the managed rules script are modelled.
class SetSieveScriptMethod extends MethodRequiringAccountId {
  final State? ifInState;
  final Map<String, Map<String, dynamic>>? create;
  final Map<String, Map<String, dynamic>>? update;
  final List<String>? destroy;

  /// Id (or `#creationId`) of the script to activate when every change
  /// succeeds. The server deactivates the previously active script.
  final String? onSuccessActivateScript;

  SetSieveScriptMethod(
    super.accountId, {
    this.ifInState,
    this.create,
    this.update,
    this.destroy,
    this.onSuccessActivateScript,
  });

  @override
  MethodName get methodName => MethodName('SieveScript/set');

  @override
  Set<CapabilityIdentifier> get requiredCapabilities => {
        CapabilityIdentifier.jmapCore,
        capabilitySieve,
      };

  @override
  Map<String, dynamic> toJson() => _accountJson(accountId)
    ..addAll({
      if (ifInState != null) 'ifInState': ifInState!.value,
      if (create != null) 'create': create,
      if (update != null) 'update': update,
      if (destroy != null) 'destroy': destroy,
      if (onSuccessActivateScript != null)
        'onSuccessActivateScript': onSuccessActivateScript,
    });

  @override
  List<Object?> get props =>
      [accountId, ifInState, create, update, destroy, onSuccessActivateScript];
}

class SetSieveScriptResponse extends MethodResponse {
  final State? oldState;
  final State? newState;
  final Map<String, SieveScript> created;
  final Set<String> updated;
  final Map<String, SetError> notCreated;
  final Map<String, SetError> notUpdated;

  SetSieveScriptResponse({
    this.oldState,
    this.newState,
    this.created = const {},
    this.updated = const {},
    this.notCreated = const {},
    this.notUpdated = const {},
  });

  static SetSieveScriptResponse deserialize(Map<String, dynamic> json) {
    Map<String, SetError> errors(Object? value) =>
        (value as Map<String, dynamic>? ?? const {}).map((key, error) =>
            MapEntry(key, SetError.fromJson(error as Map<String, dynamic>)));

    return SetSieveScriptResponse(
      oldState:
          const StateNullableConverter().fromJson(json['oldState'] as String?),
      newState:
          const StateNullableConverter().fromJson(json['newState'] as String?),
      created: (json['created'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          key,
          SieveScript.fromJson(<String, dynamic>{
            ...(value as Map<String, dynamic>),
          }),
        ),
      ),
      updated:
          (json['updated'] as Map<String, dynamic>? ?? const {}).keys.toSet(),
      notCreated: errors(json['notCreated']),
      notUpdated: errors(json['notUpdated']),
    );
  }

  @override
  List<Object?> get props =>
      [oldState, newState, created, updated, notCreated, notUpdated];
}

/// `SieveScript/validate` (RFC 9661, section 3.4).
class ValidateSieveScriptMethod extends MethodRequiringAccountId {
  final String blobId;

  ValidateSieveScriptMethod(super.accountId, this.blobId);

  @override
  MethodName get methodName => MethodName('SieveScript/validate');

  @override
  Set<CapabilityIdentifier> get requiredCapabilities => {
        CapabilityIdentifier.jmapCore,
        capabilitySieve,
      };

  @override
  Map<String, dynamic> toJson() =>
      _accountJson(accountId)..addAll({'blobId': blobId});

  @override
  List<Object?> get props => [accountId, blobId];
}

class ValidateSieveScriptResponse extends MethodResponse {
  final SetError? error;

  ValidateSieveScriptResponse({this.error});

  static ValidateSieveScriptResponse deserialize(Map<String, dynamic> json) {
    final error = json['error'];
    return ValidateSieveScriptResponse(
      error: error is Map<String, dynamic> ? SetError.fromJson(error) : null,
    );
  }

  @override
  List<Object?> get props => [error];
}

/// `Blob/upload` (RFC 9404, section 4.1) with a single text part.
class UploadTextBlobMethod extends MethodRequiringAccountId {
  final String creationId;
  final String text;
  final String type;

  UploadTextBlobMethod(
    super.accountId, {
    required this.creationId,
    required this.text,
    this.type = 'application/sieve',
  });

  @override
  MethodName get methodName => MethodName('Blob/upload');

  @override
  Set<CapabilityIdentifier> get requiredCapabilities => {
        CapabilityIdentifier.jmapCore,
        capabilityBlob,
      };

  @override
  Map<String, dynamic> toJson() => _accountJson(accountId)
    ..addAll({
      'create': {
        creationId: {
          'data': [
            {'data:asText': text},
          ],
          'type': type,
        },
      },
    });

  @override
  List<Object?> get props => [accountId, creationId, text, type];
}

class UploadTextBlobResponse extends MethodResponse {
  final Map<String, String> createdBlobIds;
  final Map<String, SetError> notCreated;

  UploadTextBlobResponse({
    this.createdBlobIds = const {},
    this.notCreated = const {},
  });

  static UploadTextBlobResponse deserialize(Map<String, dynamic> json) {
    return UploadTextBlobResponse(
      createdBlobIds: (json['created'] as Map<String, dynamic>? ?? const {})
          .map((key, value) =>
              MapEntry(key, (value as Map<String, dynamic>)['id'] as String)),
      notCreated: (json['notCreated'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(
              key, SetError.fromJson(value as Map<String, dynamic>))),
    );
  }

  @override
  List<Object?> get props => [createdBlobIds, notCreated];
}

/// `Blob/get` (RFC 9404, section 4.2) returning the blob as text.
class GetTextBlobMethod extends MethodRequiringAccountId {
  final List<String> ids;

  GetTextBlobMethod(super.accountId, this.ids);

  @override
  MethodName get methodName => MethodName('Blob/get');

  @override
  Set<CapabilityIdentifier> get requiredCapabilities => {
        CapabilityIdentifier.jmapCore,
        capabilityBlob,
      };

  @override
  Map<String, dynamic> toJson() => _accountJson(accountId)
    ..addAll({
      'ids': ids,
      'properties': ['data:asText', 'isEncodingProblem', 'isTruncated'],
    });

  @override
  List<Object?> get props => [accountId, ids];
}

class TextBlob {
  final String id;
  final String? text;
  final bool isEncodingProblem;
  final bool isTruncated;

  const TextBlob({
    required this.id,
    this.text,
    this.isEncodingProblem = false,
    this.isTruncated = false,
  });
}

class GetTextBlobResponse extends MethodResponse {
  final List<TextBlob> list;
  final List<String> notFound;

  GetTextBlobResponse({this.list = const [], this.notFound = const []});

  static GetTextBlobResponse deserialize(Map<String, dynamic> json) {
    return GetTextBlobResponse(
      list: (json['list'] as List<dynamic>? ?? const []).map((value) {
        final blob = value as Map<String, dynamic>;
        return TextBlob(
          id: blob['id'] as String,
          text: blob['data:asText'] as String?,
          isEncodingProblem: blob['isEncodingProblem'] == true,
          isTruncated: blob['isTruncated'] == true,
        );
      }).toList(),
      notFound: (json['notFound'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  @override
  List<Object?> get props => [list, notFound];
}
