import 'package:jmap_dart_client/http/converter/id_converter.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rule_filter/rule_filter/converter/rule_id_nullable_converter.dart';
import 'package:rule_filter/rule_filter/rule.dart';
import 'package:rule_filter/rule_filter/rule_action.dart';
import 'package:rule_filter/rule_filter/rule_condition.dart';
import 'package:rule_filter/rule_filter/rule_condition_group.dart';
import 'package:rule_filter/rule_filter/rule_id.dart';

part 'tmail_rule.g.dart';

@RuleIdNullableConverter()
@IdConverter()
@JsonSerializable(explicitToJson: true)
class TMailRule extends Rule {
  final RuleId? id;
  final String name;
  @JsonKey(includeIfNull: false)
  final RuleCondition? condition;
  @JsonKey(includeIfNull: false)
  final RuleConditionGroup? conditionGroup;
  final RuleAction action;

  /// Sieve backend only. The Linagora `Filter` API has no such property, so the
  /// field never reaches its JSON and defaults keep that backend unchanged.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool isEnabled;

  /// Sieve backend only: stop evaluating the following rules when this rule
  /// matches. Not serialized for the same reason as [isEnabled].
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool stopProcessing;

  TMailRule({
    this.id,
    required this.name,
    this.condition,
    this.conditionGroup,
    required this.action,
    this.isEnabled = true,
    this.stopProcessing = false,
  });

  factory TMailRule.fromJson(Map<String, dynamic> json) =>
      _$TMailRuleFromJson(json);

  Map<String, dynamic> toJson() => _$TMailRuleToJson(this);

  @override
  List<Object?> get props => [
        name,
        condition,
        action,
        conditionGroup,
        isEnabled,
        stopProcessing,
      ];

  TMailRule copyWith({
    RuleId? id,
    String? name,
    RuleCondition? condition,
    RuleAction? action,
    RuleConditionGroup? conditionGroup,
    bool? isEnabled,
    bool? stopProcessing,
  }) {
    return TMailRule(
      id: id ?? this.id,
      name: name ?? this.name,
      condition: condition ?? this.condition,
      action: action ?? this.action,
      conditionGroup: conditionGroup ?? this.conditionGroup,
      isEnabled: isEnabled ?? this.isEnabled,
      stopProcessing: stopProcessing ?? this.stopProcessing,
    );
  }

  /// Copy without the legacy single [condition] when a [conditionGroup]
  /// exists (`copyWith` cannot clear a field). Rules are sent to the server
  /// this way so that both representations never disagree.
  TMailRule withoutLegacyCondition() {
    if (conditionGroup == null) return this;
    return TMailRule(
      id: id,
      name: name,
      conditionGroup: conditionGroup,
      action: action,
      isEnabled: isEnabled,
      stopProcessing: stopProcessing,
    );
  }
}
