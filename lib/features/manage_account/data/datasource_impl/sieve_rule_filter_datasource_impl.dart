import 'dart:convert';

import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:rule_filter/sieve/sieve_account_capability.dart';
import 'package:rule_filter/sieve/sieve_rules_codec.dart';
import 'package:tmail_ui_user/features/manage_account/data/datasource/rule_filter_datasource.dart';
import 'package:tmail_ui_user/features/manage_account/data/extensions/list_tmail_rule_extensions.dart';
import 'package:tmail_ui_user/features/manage_account/data/network/sieve_rule_filter_api.dart';
import 'package:tmail_ui_user/features/manage_account/domain/exceptions/sieve_rules_exceptions.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/create_new_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/delete_email_rule_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/edit_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/main/exceptions/thrower/exception_thrower.dart';

/// Rules stored as a single Sieve script owned by the webmail.
///
/// Every write starts from the last snapshot read and sends its state as
/// `ifInState`, so a change made meanwhile (another tab, another client, the
/// automatic reply) fails with [SieveRulesConflictException] instead of being
/// overwritten. Other scripts are never changed nor deactivated.
class SieveRuleFilterDataSourceImpl extends RuleFilterDataSource {
  final SieveRuleFilterAPI _api;
  final SieveAccountCapability _capability;
  final ExceptionThrower _exceptionThrower;
  final SieveRulesCodec _codec;

  final Map<AccountId, SieveRulesSnapshot> _snapshots = {};

  SieveRuleFilterDataSourceImpl(
    this._api,
    this._capability,
    this._exceptionThrower, {
    SieveRulesCodec codec = const SieveRulesCodec(),
  }) : _codec = codec;

  @override
  Future<List<TMailRule>> getAllTMailRule(AccountId accountId) {
    return Future.sync(() async {
      final snapshot = await _refresh(accountId);
      return _rulesOf(snapshot);
    }).catchError(_exceptionThrower.throwException);
  }

  @override
  Future<List<TMailRule>> createNewEmailRuleFilter(
    AccountId accountId,
    CreateNewEmailRuleFilterRequest ruleFilterRequest,
  ) {
    return _write(accountId, ruleFilterRequest.newListTMailRules);
  }

  @override
  Future<List<TMailRule>> editEmailRuleFilter(
    AccountId accountId,
    EditEmailRuleFilterRequest ruleFilterRequest,
  ) {
    return _write(accountId, ruleFilterRequest.listTMailRulesUpdated);
  }

  @override
  Future<List<TMailRule>> deleteTMailRule(
    AccountId accountId,
    DeleteEmailRuleRequest deleteEmailRuleRequest,
  ) {
    final rules = List<TMailRule>.of(deleteEmailRuleRequest.currentEmailRules)
      ..remove(deleteEmailRuleRequest.emailRuleDelete);
    return _write(accountId, rules);
  }

  @override
  Future<List<TMailRule>> replaceAllTMailRules(
    AccountId accountId,
    List<TMailRule> rules,
  ) {
    return _write(accountId, rules);
  }

  @override
  Future<EmailRulesStatus?> getRulesStatus(AccountId accountId) {
    return Future.sync(() async {
      final snapshot = _snapshots[accountId] ?? await _refresh(accountId);
      return statusOf(snapshot);
    }).catchError(_exceptionThrower.throwException);
  }

  EmailRulesStatus statusOf(SieveRulesSnapshot snapshot) {
    final managed = snapshot.managedScript;
    final otherActive = snapshot.otherActiveScript;
    return EmailRulesStatus(
      hasManagedScript: managed != null,
      isActive: managed?.isActive == true,
      blockingScriptName: otherActive == null ? null : (otherActive.name ?? ''),
      blockedByVacation: otherActive?.name == stalwartVacationScriptName,
      readOnlyReason: _readOnlyReasonOf(snapshot),
      unsupportedFeatures: SieveRuleFeature.values
          .where((feature) => !feature.isSupportedBy(_capability))
          .toSet(),
    );
  }

  Future<SieveRulesSnapshot> _refresh(AccountId accountId) async {
    final snapshot = await _api.read(accountId);
    _snapshots[accountId] = snapshot;
    return snapshot;
  }

  List<TMailRule> _rulesOf(SieveRulesSnapshot snapshot) {
    final content = snapshot.managedContent;
    if (content == null || _readOnlyReasonOf(snapshot) != null) {
      return <TMailRule>[];
    }
    return _codec.parse(content).document?.rules ?? <TMailRule>[];
  }

  EmailRulesReadOnlyReason? _readOnlyReasonOf(SieveRulesSnapshot snapshot) {
    final content = snapshot.managedContent;
    if (snapshot.managedScript == null || content == null) return null;
    if (!content.contains(managedSieveMetadataPrefix)) {
      return EmailRulesReadOnlyReason.nameConflict;
    }
    return _codec.parse(content).isIntact
        ? null
        : EmailRulesReadOnlyReason.modifiedExternally;
  }

  Future<List<TMailRule>> _write(AccountId accountId, List<TMailRule> rules) {
    return Future.sync(() async {
      final base = _snapshots[accountId] ?? await _refresh(accountId);
      final readOnlyReason = _readOnlyReasonOf(base);
      if (readOnlyReason != null) {
        throw SieveRulesReadOnlyException(readOnlyReason);
      }

      // The comparator is recorded in the metadata, so picking the best one
      // on every write keeps reads deterministic and upgrades older scripts.
      final document = SieveRulesDocument(
        comparator: _codec.chooseComparator(_capability),
        rules: rules
            .map((rule) => rule.withoutLegacyCondition())
            .toList()
            .withIds,
      );
      _codec.ensureSupported(document, _capability);
      final content = _codec.generate(document, capability: _capability);

      final size = utf8.encode(content).length;
      final maxSize = _capability.maxSizeScript;
      if (maxSize != null && size > maxSize) {
        throw SieveScriptTooLargeException(size, maxSize);
      }

      // Activating would deactivate any other script (the automatic reply or
      // a filter from another client), so it only happens when none is active.
      final activate = base.otherActiveScript == null;

      try {
        await _api.save(
          accountId,
          base: base,
          content: content,
          activate: activate,
        );
      } on SieveRulesConflictException {
        _snapshots.remove(accountId);
        rethrow;
      }

      final stored = await _refresh(accountId);
      final storedRules = _rulesOf(stored);
      final verified = _readOnlyReasonOf(stored) == null &&
          stored.managedContent != null &&
          _sameRules(storedRules, document.rules) &&
          (!activate || stored.managedScript?.isActive == true);
      if (!verified) {
        throw const SieveRulesVerificationException();
      }
      return storedRules;
    }).catchError(_exceptionThrower.throwException);
  }

  bool _sameRules(List<TMailRule> stored, List<TMailRule> sent) {
    if (stored.length != sent.length) return false;
    for (var index = 0; index < stored.length; index++) {
      if (stored[index].withoutLegacyCondition() !=
          sent[index].withoutLegacyCondition()) {
        return false;
      }
    }
    return true;
  }
}
