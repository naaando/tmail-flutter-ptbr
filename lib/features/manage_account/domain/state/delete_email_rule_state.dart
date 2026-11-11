import 'package:core/core.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';

class DeleteEmailRuleSuccess extends UIState {
  final List<TMailRule>? rules;
  final EmailRulesStatus? status;

  DeleteEmailRuleSuccess(this.rules, {this.status});

  @override
  List<Object?> get props => [rules, status];
}

class DeleteEmailRuleFailure extends FeatureFailure {

  DeleteEmailRuleFailure(dynamic exception) : super(exception: exception);
}