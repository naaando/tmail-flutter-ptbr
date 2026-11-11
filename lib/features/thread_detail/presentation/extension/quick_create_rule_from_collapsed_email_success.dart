import 'package:tmail_ui_user/features/manage_account/domain/state/create_new_rule_filter_state.dart';
import 'package:tmail_ui_user/features/thread_detail/presentation/thread_detail_controller.dart';

extension QuickCreateRuleFromCollapsedEmailSuccess on ThreadDetailController {
  void quickCreateRuleFromCollapsedEmailSuccess(
    CreateNewRuleFilterSuccess success,
  ) {
    if (success.newListRules.isEmpty) return;
    // Same message as the other entry points, including the warning when the
    // rules were saved but another script keeps them from running.
    toastManager.showMessageSuccess(success);
  }
}
