import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';
import 'ore_surface.dart';

class OreTextField extends StatelessWidget {
  const OreTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.enabled = true,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.prefix,
    this.suffix,
    this.contentPadding,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onEditingComplete,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final bool enabled;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final Widget? prefix;
  final Widget? suffix;
  final EdgeInsetsGeometry? contentPadding;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final colors = theme.colors;
    final depthUnit = theme.borderWidth;
    final highlightDepth = 0.0;
    final shadowDepth = depthUnit * 2;

    final surfaceColor = enabled ? colors.surfaceDark : colors.surface;
    final borderColor = enabled ? colors.border : colors.borderLight;
    final textColor = enabled ? colors.textPrimary : colors.textDisabled;

    final isSingleLine =
        (maxLines ?? 1) == 1 && (minLines ?? 1) == 1;
    final textAlignVertical =
        isSingleLine ? TextAlignVertical.center : TextAlignVertical.top;
    final resolvedPadding = contentPadding ??
        (isSingleLine
            ? EdgeInsets.symmetric(
                horizontal: OreTokens.gapMd,
                vertical: math.max(
                  0,
                  (OreTokens.controlHeightMd -
                          ((theme.typography.body.fontSize ?? 14) *
                              (theme.typography.body.height ?? 1.0))) /
                      2,
                ),
              )
            : EdgeInsets.symmetric(
                horizontal: OreTokens.gapMd,
                vertical: OreTokens.gapSm,
              ));
    final hintStyle =
        theme.typography.body.copyWith(color: colors.textMuted);
    final hintOffset = depthUnit * OreTokens.inputHintOffsetUnits;
    final hintWidget = isSingleLine && hintText != null
        ? Transform.translate(
            offset: Offset(0, hintOffset),
            child: Text(
              hintText!,
              style: hintStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          )
        : null;

    final textField = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      onEditingComplete: onEditingComplete,
      onSubmitted: onSubmitted,
      style: theme.typography.body.copyWith(color: textColor),
      textAlignVertical: textAlignVertical,
      cursorColor: colors.success,
      cursorWidth: depthUnit * 0.5,
      cursorRadius: Radius.zero,
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        hintText: hintWidget == null ? hintText : null,
        hintStyle: hintStyle,
        hint: hintWidget,
        contentPadding: resolvedPadding,
        prefixIcon: prefix,
        suffixIcon: suffix,
      ),
    );

    Widget field = OreSurface(
      color: surfaceColor,
      borderColor: borderColor,
      highlightColor: Colors.transparent,
      shadowColor: borderColor.withValues(alpha: 0.6),
      borderWidth: theme.borderWidth,
      depth: shadowDepth,
      highlightDepth: highlightDepth,
      shadowDepth: shadowDepth,
      shadowOnTop: true,
      padding: EdgeInsets.zero,
      child: isSingleLine
          ? Align(
              alignment: Alignment.centerLeft,
              child: textField,
            )
          : textField,
    );

    if (isSingleLine) {
      field = SizedBox(height: OreTokens.controlHeightMd, child: field);
    }

    return TextSelectionTheme(
      data: TextSelectionThemeData(
        cursorColor: colors.success,
        selectionColor: colors.selection,
      ),
      child: field,
    );
  }
}
