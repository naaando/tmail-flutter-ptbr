import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/responsive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rule_filter/rule_filter/rule_action.dart';
import 'package:rule_filter/rule_filter/rule_append_in.dart';
import 'package:rule_filter/rule_filter/rule_condition.dart';
import 'package:rule_filter/rule_filter/rule_condition_group.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/base/model/ui_keys.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/email_rule_item_widget.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';

TMailRule _rule({bool enabled = true}) => TMailRule(
      name: 'Relatórios',
      conditionGroup: RuleConditionGroup(
        conditionCombiner: ConditionCombiner.AND,
        conditions: [
          RuleCondition(field: Field.subject, comparator: Comparator.contains, value: 'x'),
        ],
      ),
      action: RuleAction(appendIn: RuleAppendIn(mailboxIds: const [])),
      isEnabled: enabled,
    );

void main() {
  final imagePaths = ImagePaths();
  final responsiveUtils = ResponsiveUtils();

  Future<void> pump(WidgetTester tester, Widget child, {double width = 1600}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('pt', 'BR'),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocalizationService.supportedLocales,
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Linagora rows show no ordering controls', (tester) async {
    await pump(tester, EmailRulesItemWidget(
      imagePaths: imagePaths,
      responsiveUtils: responsiveUtils,
      rule: _rule(),
    ));

    expect(find.byKey(const ValueKey('${UiKeys.toggleEmailRuleButton}_Relatórios')), findsNothing);
    expect(find.byKey(const ValueKey('${UiKeys.moveUpEmailRuleButton}_Relatórios')), findsNothing);
  });

  testWidgets('Sieve rows toggle and move through callbacks', (tester) async {
    final calls = <String>[];
    await pump(tester, EmailRulesItemWidget(
      imagePaths: imagePaths,
      responsiveUtils: responsiveUtils,
      rule: _rule(),
      showOrderingControls: true,
      canMoveUp: true,
      canMoveDown: false,
      onToggleEmailRuleAction: (_) => calls.add('toggle'),
      onMoveUpEmailRuleAction: (_) => calls.add('up'),
      onMoveDownEmailRuleAction: (_) => calls.add('down'),
    ));

    await tester.tap(find.byKey(const ValueKey('${UiKeys.toggleEmailRuleButton}_Relatórios')));
    await tester.tap(find.byKey(const ValueKey('${UiKeys.moveUpEmailRuleButton}_Relatórios')));
    await tester.tap(find.byKey(const ValueKey('${UiKeys.moveDownEmailRuleButton}_Relatórios')));
    await tester.pump();

    expect(calls, ['toggle', 'up'], reason: 'move down is disabled on the last row');
  });

  testWidgets('disabled rules and missing folders are labelled', (tester) async {
    await pump(tester, EmailRulesItemWidget(
      imagePaths: imagePaths,
      responsiveUtils: responsiveUtils,
      rule: _rule(enabled: false),
      showOrderingControls: true,
      hasMissingMailbox: true,
    ));

    expect(
      find.textContaining('Desativada · Pasta não encontrada, entrega na Caixa de entrada'),
      findsOneWidget,
    );
  });

  testWidgets('mobile keeps the switch and leaves moves to the menu', (tester) async {
    await pump(
      tester,
      EmailRulesItemWidget(
        imagePaths: imagePaths,
        responsiveUtils: responsiveUtils,
        rule: _rule(),
        showOrderingControls: true,
        canMoveUp: true,
        canMoveDown: true,
      ),
      width: 390,
    );

    expect(find.byKey(const ValueKey('${UiKeys.toggleEmailRuleButton}_Relatórios')), findsOneWidget);
    expect(find.byKey(const ValueKey('${UiKeys.moveUpEmailRuleButton}_Relatórios')), findsNothing);
    expect(find.byKey(const ValueKey('${UiKeys.moreEmailRuleButton}_Relatórios')), findsOneWidget);
  });
}
