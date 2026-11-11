import 'package:collection/collection.dart';
import 'package:core/utils/app_logger.dart';
import 'package:jmap_dart_client/http/http_client.dart';
import 'package:jmap_dart_client/http/converter/account_id_converter.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/error/method/error_method_response.dart';
import 'package:jmap_dart_client/jmap/core/error/method/exception/error_method_response_exception.dart';
import 'package:jmap_dart_client/jmap/core/error/set_error.dart';
import 'package:jmap_dart_client/jmap/core/method/method.dart';
import 'package:jmap_dart_client/jmap/core/method/method_response.dart';
import 'package:jmap_dart_client/jmap/core/state.dart';
import 'package:jmap_dart_client/jmap/jmap_request.dart';
import 'package:rule_filter/sieve/sieve_methods.dart';
import 'package:rule_filter/sieve/sieve_rules_codec.dart';
import 'package:rule_filter/sieve/sieve_script.dart';
import 'package:tmail_ui_user/features/manage_account/domain/exceptions/sieve_rules_exceptions.dart';
import 'package:jmap_dart_client/jmap/core/capability/capability_identifier.dart';
import 'package:jmap_dart_client/jmap/core/request/request_invocation.dart';

/// Name Stalwart gives to the script behind `VacationResponse`.
const String stalwartVacationScriptName = 'vacation';

/// What the server holds at a given state: every script (metadata only) and,
/// for the managed one, its content.
class SieveRulesSnapshot {
  final State? state;
  final List<SieveScript> scripts;
  final SieveScript? managedScript;
  final String? managedContent;

  const SieveRulesSnapshot({
    required this.state,
    required this.scripts,
    this.managedScript,
    this.managedContent,
  });

  /// Another script is active. Activating the managed script would
  /// deactivate it, which the webmail never does on its own.
  SieveScript? get otherActiveScript => scripts.firstWhereOrNull(
        (script) => script.isActive && script.id != managedScript?.id,
      );
}

/// Accesses JMAP for Sieve (RFC 9661) as the signed-in user. Script contents
/// travel through `Blob/upload` and `Blob/get` (RFC 9404) inside the same
/// JMAP endpoint, so no extra service or credential is involved.
class SieveRuleFilterAPI {
  final HttpClient _httpClient;

  SieveRuleFilterAPI(this._httpClient);

  Future<SieveRulesSnapshot> read(AccountId accountId) async {
    final getMethod = GetSieveScriptMethod(
      accountId,
      properties: const ['name', 'blobId', 'isActive'],
    );
    final getResponse = await _execute(
      getMethod,
      GetSieveScriptResponse.deserialize,
    );

    final managedScript = getResponse.list.firstWhereOrNull(
      (script) => script.name == managedSieveScriptName,
    );
    String? content;
    final blobId = managedScript?.blobId;
    if (blobId != null) {
      final blobResponse = await _execute(
        GetTextBlobMethod(accountId, [blobId]),
        GetTextBlobResponse.deserialize,
      );
      final blob = blobResponse.list.firstWhereOrNull((b) => b.id == blobId);
      if (blob == null ||
          blob.text == null ||
          blob.isTruncated ||
          blob.isEncodingProblem) {
        throw const SieveRulesReadException('blobNotReadable');
      }
      content = blob.text;
    }

    return SieveRulesSnapshot(
      state: getResponse.state,
      scripts: getResponse.list,
      managedScript: managedScript,
      managedContent: content,
    );
  }

  /// Ids of the account's mailboxes, used to flag rules whose target folder
  /// was deleted (the script then files into INBOX).
  Future<Set<String>> mailboxIds(AccountId accountId) async {
    final response = await _execute(
      _GetMailboxIdsMethod(accountId),
      _GetMailboxIdsResponse.deserialize,
    );
    return response.ids;
  }

  /// Uploads, validates and stores the managed script. Activation only
  /// happens when [activate] is true and every change succeeds.
  Future<void> save(
    AccountId accountId, {
    required SieveRulesSnapshot base,
    required String content,
    required bool activate,
  }) async {
    const blobCreationId = 'rules';
    final upload = await _execute(
      UploadTextBlobMethod(
        accountId,
        creationId: blobCreationId,
        text: content,
      ),
      UploadTextBlobResponse.deserialize,
    );
    final blobId = upload.createdBlobIds[blobCreationId];
    if (blobId == null) {
      throw _rejected(upload.notCreated[blobCreationId], 'blobNotCreated');
    }

    final validation = await _execute(
      ValidateSieveScriptMethod(accountId, blobId),
      ValidateSieveScriptResponse.deserialize,
    );
    if (validation.error != null) {
      throw _rejected(validation.error, 'invalidScript');
    }

    const scriptCreationId = 'managed';
    final managedId = base.managedScript?.id.value;
    final setResponse = await _execute(
      SetSieveScriptMethod(
        accountId,
        ifInState: base.state,
        create: managedId == null
            ? {
                scriptCreationId: {
                  'name': managedSieveScriptName,
                  'blobId': blobId,
                },
              }
            : null,
        update: managedId == null
            ? null
            : {
                managedId: {'blobId': blobId},
              },
        onSuccessActivateScript: activate
            ? (managedId ?? '#$scriptCreationId')
            : null,
      ),
      SetSieveScriptResponse.deserialize,
    );

    if (managedId == null) {
      if (!setResponse.created.containsKey(scriptCreationId)) {
        throw _rejected(
          setResponse.notCreated[scriptCreationId],
          'notCreated',
        );
      }
    } else if (!setResponse.updated.contains(managedId)) {
      throw _rejected(setResponse.notUpdated[managedId], 'notUpdated');
    }
  }

  Future<T> _execute<T extends MethodResponse>(
    MethodRequiringAccountId method,
    T Function(Map<String, dynamic>) deserialize,
  ) async {
    final requestBuilder =
        JmapRequestBuilder(_httpClient, ProcessingInvocation());
    final invocation = requestBuilder.invocation(method);
    final response = await (requestBuilder
          ..usings(method.requiredCapabilities))
        .build()
        .execute();
    try {
      final result = response.parse<T>(
        invocation.methodCallId,
        deserialize,
        methodName: method.methodName,
      );
      if (result == null) {
        throw SieveRulesReadException(
          'emptyResponse:${method.methodName.value}',
        );
      }
      return result;
    } on ErrorMethodResponseException catch (error) {
      final errorResponse = error.errorResponse;
      final type = errorResponse is ErrorMethodResponse
          ? errorResponse.type.value
          : 'unknown';
      logWarning(
        'SieveRuleFilterAPI::${method.methodName.value}: method error $type',
      );
      if (type == 'stateMismatch') {
        throw const SieveRulesConflictException();
      }
      rethrow;
    }
  }

  SieveScriptRejectedException _rejected(SetError? error, String fallback) {
    return SieveScriptRejectedException(
      error?.type.value ?? fallback,
      description: error?.description,
    );
  }
}

class _GetMailboxIdsMethod extends MethodRequiringAccountId {
  _GetMailboxIdsMethod(super.accountId);

  @override
  MethodName get methodName => MethodName('Mailbox/get');

  @override
  Set<CapabilityIdentifier> get requiredCapabilities => {
        CapabilityIdentifier.jmapCore,
        CapabilityIdentifier.jmapMail,
      };

  @override
  Map<String, dynamic> toJson() => {
        'accountId': const AccountIdConverter().toJson(accountId),
        'properties': ['id'],
      };

  @override
  List<Object?> get props => [accountId];
}

class _GetMailboxIdsResponse extends MethodResponse {
  final Set<String> ids;

  _GetMailboxIdsResponse(this.ids);

  static _GetMailboxIdsResponse deserialize(Map<String, dynamic> json) {
    return _GetMailboxIdsResponse(
      (json['list'] as List<dynamic>? ?? const [])
          .map((value) => (value as Map<String, dynamic>)['id'] as String)
          .toSet(),
    );
  }

  @override
  List<Object?> get props => [ids];
}
