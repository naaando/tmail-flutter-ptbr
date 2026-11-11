import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';

class GettingAllRules extends LoadingState {}

class GetAllRulesSuccess extends UIState {
  final List<TMailRule>? rules;
  final EmailRulesStatus? status;

  GetAllRulesSuccess(this.rules, {this.status});

  @override
  List<Object?> get props => [rules, status];
}

class GetAllRulesFailure extends FeatureFailure {

  GetAllRulesFailure(dynamic exception) : super(exception: exception);
}