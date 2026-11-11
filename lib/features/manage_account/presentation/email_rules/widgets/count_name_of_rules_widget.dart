import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:flutter/material.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

class CountNameOfRulesWidget extends StatelessWidget {

  final int countRules;
  final EdgeInsetsGeometry? margin;

  /// Secondary text after the count, e.g. that rules run in order.
  final String? hint;

  const CountNameOfRulesWidget({
    super.key,
    required this.countRules,
    this.margin,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? const EdgeInsetsDirectional.only(top: 38),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              AppLocalizations.of(context).headerNameOfRules,
              style: ThemeUtils.textStyleInter600().copyWith(
                fontSize: 14,
                height: 20 / 14,
                letterSpacing: 0.25,
                color: AppColor.gray424244,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Text(
            ' ${countRules > 999 ? '999+' : countRules.toString()}',
            style: ThemeUtils.textStyleInter400.copyWith(
              fontSize: 14,
              height: 20 / 14,
              letterSpacing: 0.25,
              color: AppColor.gray424244,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (hint != null)
            Flexible(
              child: Text(
                ' · $hint',
                style: ThemeUtils.textStyleBodyBody3(
                  color: AppColor.steelGray400,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
        ],
      ),
    );
  }
}
