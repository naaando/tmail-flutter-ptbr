import 'package:core/utils/app_logger.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/features/manage_account/domain/repository/rule_filter_repository.dart';

extension RuleFilterRepositoryStatusExtension on RuleFilterRepository {
  /// The status only enriches a successful operation; failing to read it must
  /// not turn that success into an error.
  Future<EmailRulesStatus?> getRulesStatusOrNull(AccountId accountId) async {
    try {
      return await getRulesStatus(accountId);
    } catch (error) {
      logWarning('RuleFilterRepository::getRulesStatusOrNull(): $error');
      return null;
    }
  }
}
