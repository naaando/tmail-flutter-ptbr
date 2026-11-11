import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:tmail_ui_user/features/manage_account/domain/repository/rule_filter_repository.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/sync_email_rules_with_vacation_state.dart';

/// Keeps the email rules and the vacation reply consistent on servers where
/// both are Sieve scripts and only one can be active:
/// - vacation on: report that rules with enabled entries are now paused;
/// - vacation off: activate the managed rules again when nothing else is
///   active (never deactivating another script).
class SyncEmailRulesWithVacationInteractor {
  final RuleFilterRepository _ruleFilterRepository;

  SyncEmailRulesWithVacationInteractor(this._ruleFilterRepository);

  Stream<Either<Failure, Success>> execute(
    AccountId accountId, {
    required bool vacationEnabled,
  }) async* {
    try {
      final rules = await _ruleFilterRepository.getAllTMailRule(accountId);
      final status = await _ruleFilterRepository.getRulesStatus(accountId);
      if (status == null || !status.hasManagedScript) return;
      final hasEnabledRules = rules.any((rule) => rule.isEnabled);

      if (vacationEnabled) {
        if (status.blockedByVacation && hasEnabledRules) {
          yield Right(EmailRulesPausedByVacation());
        }
        return;
      }

      if (status.canActivate) {
        await _ruleFilterRepository.replaceAllTMailRules(
          accountId,
          rules,
          currentRules: rules,
        );
        if (hasEnabledRules) {
          yield Right(EmailRulesResumedAfterVacation());
        }
      }
    } catch (exception) {
      yield Left(SyncEmailRulesWithVacationFailure(exception));
    }
  }
}
