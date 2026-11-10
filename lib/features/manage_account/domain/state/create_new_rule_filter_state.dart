import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';

class CreateNewRuleFilterSuccess extends UIState {

  final List<TMailRule> newListRules;
  final EmailRulesStatus? status;

  CreateNewRuleFilterSuccess(this.newListRules, {this.status});

  @override
  List<Object?> get props => [newListRules, status];
}

class CreateNewRuleFilterFailure extends FeatureFailure {

  CreateNewRuleFilterFailure(dynamic exception) : super(exception: exception);
}