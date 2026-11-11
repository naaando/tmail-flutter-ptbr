import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';

class EditEmailRuleFilterSuccess extends UIState {

  final List<TMailRule> listRulesUpdated;
  final EmailRulesStatus? status;

  EditEmailRuleFilterSuccess(this.listRulesUpdated, {this.status});

  @override
  List<Object?> get props => [listRulesUpdated, status];
}

class EditEmailRuleFilterFailure extends FeatureFailure {

  EditEmailRuleFilterFailure(dynamic exception) : super(exception: exception);
}