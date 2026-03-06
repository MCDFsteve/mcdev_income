library ore_material;

import 'package:flutter/material.dart'
    hide
        ElevatedButton,
        OutlinedButton,
        TextButton,
        SegmentedButton,
        ButtonSegment;
import 'package:oreui_flutter/oreui_flutter.dart';

export 'package:flutter/material.dart'
    hide
        ElevatedButton,
        OutlinedButton,
        TextButton,
        SegmentedButton,
        ButtonSegment;
export 'package:oreui_flutter/oreui_flutter.dart'
    show
        OreButton,
        OreButtonSize,
        OreButtonVariant,
        OreChoiceButtons,
        OreChoiceDescription,
        OreColors,
        OreTheme,
        OreThemeBuilder,
        OreThemeController,
        OreThemeData,
        OreThemeProvider,
        OreTokens,
        OreTypography;

class ElevatedButton extends StatelessWidget {
  const ElevatedButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    this.focusNode,
    this.autofocus = false,
    Clip clipBehavior = Clip.none,
    required this.child,
    this.icon,
  });

  factory ElevatedButton.icon({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    Clip clipBehavior = Clip.none,
    required Widget icon,
    required Widget label,
  }) {
    return ElevatedButton(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      clipBehavior: clipBehavior,
      child: label,
      icon: icon,
    );
  }

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return _OreButtonAdapter(
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      variant: OreButtonVariant.primary,
      size: OreButtonSize.md,
      leading: icon,
      child: child,
    );
  }
}

class OutlinedButton extends StatelessWidget {
  const OutlinedButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    this.focusNode,
    this.autofocus = false,
    Clip clipBehavior = Clip.none,
    required this.child,
    this.icon,
  });

  factory OutlinedButton.icon({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    Clip clipBehavior = Clip.none,
    required Widget icon,
    required Widget label,
  }) {
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      clipBehavior: clipBehavior,
      child: label,
      icon: icon,
    );
  }

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return _OreButtonAdapter(
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      variant: OreButtonVariant.secondary,
      size: OreButtonSize.md,
      leading: icon,
      child: child,
    );
  }
}

class TextButton extends StatelessWidget {
  const TextButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    this.focusNode,
    this.autofocus = false,
    Clip clipBehavior = Clip.none,
    required this.child,
    this.icon,
  });

  factory TextButton.icon({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    Clip clipBehavior = Clip.none,
    required Widget icon,
    required Widget label,
  }) {
    return TextButton(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      clipBehavior: clipBehavior,
      child: label,
      icon: icon,
    );
  }

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return _OreButtonAdapter(
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      variant: OreButtonVariant.ghost,
      size: OreButtonSize.sm,
      leading: icon,
      child: child,
    );
  }
}

class _OreButtonAdapter extends StatelessWidget {
  const _OreButtonAdapter({
    required this.onPressed,
    required this.onLongPress,
    required this.focusNode,
    required this.autofocus,
    required this.variant,
    required this.size,
    required this.leading,
    required this.child,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final OreButtonVariant variant;
  final OreButtonSize size;
  final Widget? leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OreButton(
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      variant: variant,
      size: size,
      leading: _wrapIcon(context, leading),
      child: child,
    );
  }

  Widget? _wrapIcon(BuildContext context, Widget? icon) {
    if (icon == null) {
      return null;
    }
    final colors = OreTheme.of(context).colors;
    final enabled = onPressed != null;
    final color = enabled
        ? switch (variant) {
            OreButtonVariant.primary ||
            OreButtonVariant.danger =>
              colors.textInverse,
            OreButtonVariant.secondary || OreButtonVariant.ghost =>
              colors.textPrimary,
          }
        : colors.textDisabled;
    return IconTheme.merge(
      data: IconThemeData(color: color),
      child: icon,
    );
  }
}

@immutable
class ButtonSegment<T> {
  const ButtonSegment({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final Widget label;
  final Widget? icon;
}

class SegmentedButton<T> extends StatelessWidget {
  const SegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.showSelectedIcon,
    this.multiSelectionEnabled,
    this.emptySelectionAllowed,
    this.style,
    this.selectedIcon,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool? showSelectedIcon;
  final bool? multiSelectionEnabled;
  final bool? emptySelectionAllowed;
  final ButtonStyle? style;
  final Widget? selectedIcon;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedIndex = _resolveSelectedIndex();
    final items = segments.map(_buildSegmentItem).toList();

    return OreChoiceButtons(
      items: items,
      selectedIndex: selectedIndex,
      onChanged: onSelectionChanged == null
          ? null
          : (index) {
              if (index < 0 || index >= segments.length) {
                return;
              }
              onSelectionChanged?.call({segments[index].value});
            },
    );
  }

  int _resolveSelectedIndex() {
    for (var i = 0; i < segments.length; i++) {
      if (selected.contains(segments[i].value)) {
        return i;
      }
    }
    return 0;
  }

  Widget _buildSegmentItem(ButtonSegment<T> segment) {
    final icon = segment.icon;
    if (icon == null) {
      return segment.label;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        SizedBox(width: OreTokens.gapXs),
        segment.label,
      ],
    );
  }
}
