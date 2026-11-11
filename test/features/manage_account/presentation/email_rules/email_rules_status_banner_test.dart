import 'package:core/presentation/resources/image_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/email_rules_status_banner.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';

void main() {
  var activations = 0;

  Future<void> pump(WidgetTester tester, EmailRulesStatus? status) async {
    activations = 0;
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('pt', 'BR'),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocalizationService.supportedLocales,
      home: Scaffold(
        body: EmailRulesStatusBanner(
          imagePaths: ImagePaths(),
          status: status,
          onActivate: () => activations++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing when active or on Linagora', (tester) async {
    await pump(tester, null);
    expect(find.byType(Text), findsNothing);
    await pump(tester, const EmailRulesStatus(hasManagedScript: true, isActive: true));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('saved but idle offers activation', (tester) async {
    await pump(tester, const EmailRulesStatus(hasManagedScript: true, isActive: false));
    expect(find.textContaining('não estão em execução'), findsOneWidget);
    await tester.tap(find.text('Ativar regras'));
    expect(activations, 1);
  });

  testWidgets('vacation and foreign scripts explain without an action', (tester) async {
    await pump(tester, const EmailRulesStatus(
      hasManagedScript: true,
      isActive: false,
      blockingScriptName: 'vacation',
      blockedByVacation: true,
    ));
    expect(find.textContaining('pausadas'), findsOneWidget);
    expect(find.text('Ativar regras'), findsNothing);

    await pump(tester, const EmailRulesStatus(
      hasManagedScript: false,
      isActive: false,
      blockingScriptName: 'roundcube',
    ));
    expect(find.textContaining('"roundcube"'), findsOneWidget);
    expect(find.textContaining('Novas regras'), findsOneWidget);
  });

  testWidgets('read-only states win over activation', (tester) async {
    await pump(tester, const EmailRulesStatus(
      hasManagedScript: true,
      isActive: false,
      readOnlyReason: EmailRulesReadOnlyReason.nameConflict,
    ));
    expect(find.textContaining('"twake-mail-rules"'), findsOneWidget);
    expect(find.text('Ativar regras'), findsNothing);
  });
}
