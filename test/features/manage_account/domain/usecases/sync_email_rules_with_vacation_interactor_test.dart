import 'package:core/presentation/state/success.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:rule_filter/rule_filter/rule_action.dart';
import 'package:rule_filter/rule_filter/rule_append_in.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/create_new_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/delete_email_rule_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/edit_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/features/manage_account/domain/repository/rule_filter_repository.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/sync_email_rules_with_vacation_state.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/sync_email_rules_with_vacation_interactor.dart';

class _Repository implements RuleFilterRepository {
  _Repository(this.rules, this.status);

  final List<TMailRule> rules;
  EmailRulesStatus? status;
  int writes = 0;

  @override
  Future<List<TMailRule>> getAllTMailRule(AccountId accountId) async => rules;

  @override
  Future<EmailRulesStatus?> getRulesStatus(AccountId accountId) async => status;

  @override
  Future<List<TMailRule>> replaceAllTMailRules(
    AccountId accountId,
    List<TMailRule> rules, {
    List<TMailRule>? currentRules,
  }) async {
    writes++;
    return rules;
  }

  @override
  Future<List<TMailRule>> createNewEmailRuleFilter(AccountId a, CreateNewEmailRuleFilterRequest r) =>
      throw UnimplementedError();
  @override
  Future<List<TMailRule>> deleteTMailRule(AccountId a, DeleteEmailRuleRequest r) =>
      throw UnimplementedError();
  @override
  Future<List<TMailRule>> editEmailRuleFilter(AccountId a, EditEmailRuleFilterRequest r) =>
      throw UnimplementedError();
}

final _rule = TMailRule(name: 'A', action: RuleAction(appendIn: RuleAppendIn(mailboxIds: const [])));

void main() {
  final accountId = AccountId(Id('acc'));

  Future<List<Success>> run(_Repository repository, bool vacationEnabled) async {
    final states = await SyncEmailRulesWithVacationInteractor(repository)
        .execute(accountId, vacationEnabled: vacationEnabled)
        .toList();
    return states.map((state) => state.getOrElse(() => throw state)).toList();
  }

  test('reports paused rules when the vacation reply takes over', () async {
    final repository = _Repository([_rule], const EmailRulesStatus(
      hasManagedScript: true,
      isActive: false,
      blockingScriptName: 'vacation',
      blockedByVacation: true,
    ));

    expect(await run(repository, true), [isA<EmailRulesPausedByVacation>()]);
    expect(repository.writes, 0);
  });

  test('activates the rules again when nothing else is active', () async {
    final repository = _Repository([_rule], const EmailRulesStatus(
      hasManagedScript: true,
      isActive: false,
    ));

    expect(await run(repository, false), [isA<EmailRulesResumedAfterVacation>()]);
    expect(repository.writes, 1);
  });

  test('never activates over another active script', () async {
    final repository = _Repository([_rule], const EmailRulesStatus(
      hasManagedScript: true,
      isActive: false,
      blockingScriptName: 'roundcube',
    ));

    expect(await run(repository, false), isEmpty);
    expect(repository.writes, 0);
  });

  test('does nothing without a managed script or on Linagora', () async {
    expect(await run(_Repository([], const EmailRulesStatus(hasManagedScript: false, isActive: false)), false), isEmpty);
    expect(await run(_Repository([_rule], null), true), isEmpty);
  });
}
