import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/extensions/rule_filter_repository_status_extension.dart';
import 'package:tmail_ui_user/features/manage_account/domain/repository/rule_filter_repository.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/update_email_rules_state.dart';

/// Stores the whole ordered list: used to reorder, enable or disable rules.
class UpdateEmailRulesInteractor {
  final RuleFilterRepository _ruleFilterRepository;

  UpdateEmailRulesInteractor(this._ruleFilterRepository);

  Stream<Either<Failure, Success>> execute(
    AccountId accountId,
    List<TMailRule> rules,
  ) async* {
    try {
      final result = await _ruleFilterRepository.replaceAllTMailRules(accountId, rules);
      final status = await _ruleFilterRepository.getRulesStatusOrNull(accountId);
      yield Right(UpdateEmailRulesSuccess(result, status: status));
    } catch (exception) {
      yield Left(UpdateEmailRulesFailure(exception));
    }
  }
}
