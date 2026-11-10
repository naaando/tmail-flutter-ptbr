import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:core/presentation/views/button/tmail_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Notice shown above the email rules and in the rule editor: the rules are
/// not running, cannot be edited here, or some options are unavailable.
/// Same look as `ForwardWarningBanner`; [actionLabel] adds a single action.
class EmailRulesNoticeBanner extends StatelessWidget {
  final ImagePaths imagePaths;
  final String message;
  final bool isWarning;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isActionLoading;
  final EdgeInsetsGeometry? margin;

  const EmailRulesNoticeBanner({
    super.key,
    required this.imagePaths,
    required this.message,
    this.isWarning = false,
    this.actionLabel,
    this.onAction,
    this.isActionLoading = false,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: margin,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          color: AppColor.lightGrayEAEDF2,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SvgPicture.asset(
                  imagePaths.icInfoCircleOutline,
                  width: 20,
                  height: 20,
                  fit: BoxFit.fill,
                  colorFilter: (isWarning
                          ? AppColor.colorQuotaWarning
                          : AppColor.steelGray400)
                      .asFilter(),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      message,
                      style: ThemeUtils.textStyleBodyBody3(
                        color: AppColor.steelGray400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (actionLabel != null && onAction != null)
              TMailButtonWidget(
                text: actionLabel!,
                isLoading: isActionLoading,
                backgroundColor: Colors.transparent,
                textStyle: ThemeUtils.textStyleM3LabelLarge(
                  color: AppColor.primaryMain,
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                onTapActionCallback: isActionLoading ? null : onAction,
              ),
          ],
        ),
      ),
    );
  }
}
