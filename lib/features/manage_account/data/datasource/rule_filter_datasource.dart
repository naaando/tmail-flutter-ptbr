import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/create_new_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/delete_email_rule_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/edit_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';

abstract class RuleFilterDataSource {
  Future<List<TMailRule>> getAllTMailRule(AccountId accountId);

  Future<List<TMailRule>> deleteTMailRule(AccountId accountId, DeleteEmailRuleRequest deleteEmailRuleRequest);

  Future<List<TMailRule>> createNewEmailRuleFilter(AccountId accountId, CreateNewEmailRuleFilterRequest ruleFilterRequest);

  Future<List<TMailRule>> editEmailRuleFilter(AccountId accountId, EditEmailRuleFilterRequest ruleFilterRequest);

  /// Replaces the whole ordered list (reorder, enable or disable a rule).
  /// [currentRules] is the list the change was made from; backends with
  /// optimistic concurrency refuse the write when it is no longer current.
  Future<List<TMailRule>> replaceAllTMailRules(
    AccountId accountId,
    List<TMailRule> rules, {
    List<TMailRule>? currentRules,
  });

  /// Server-side state of the rules; `null` when the backend has none.
  Future<EmailRulesStatus?> getRulesStatus(AccountId accountId);
}
