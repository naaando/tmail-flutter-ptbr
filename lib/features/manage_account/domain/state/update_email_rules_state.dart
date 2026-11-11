import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';

/// Result of reordering, enabling or disabling rules.
class UpdateEmailRulesSuccess extends UIState {
  final List<TMailRule> rules;
  final EmailRulesStatus? status;

  UpdateEmailRulesSuccess(this.rules, {this.status});

  @override
  List<Object?> get props => [rules, status];
}

class UpdateEmailRulesFailure extends FeatureFailure {
  UpdateEmailRulesFailure(dynamic exception) : super(exception: exception);
}
