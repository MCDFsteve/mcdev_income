library ore_material;

import 'package:flutter/material.dart'
    hide
        Card,
        DropdownButton,
        DropdownButtonFormField,
        DropdownButtonHideUnderline,
        DropdownMenuItem,
        ElevatedButton,
        OutlinedButton,
        TextButton,
        Scrollbar,
        TextField,
        SegmentedButton,
        ButtonSegment;
import 'package:oreui_flutter/oreui_flutter.dart';

export 'package:flutter/material.dart'
    hide
        Card,
        DropdownButton,
        DropdownButtonFormField,
        DropdownButtonHideUnderline,
        DropdownMenuItem,
        ElevatedButton,
        OutlinedButton,
        TextButton,
        Scrollbar,
        TextField,
        SegmentedButton,
        ButtonSegment;
export 'package:oreui_flutter/oreui_flutter.dart'
    show
        OreButton,
        OreButtonSize,
        OreButtonVariant,
        OreCard,
        OreChoiceButtons,
        OreChoiceDescription,
        OreChoiceDock,
        OreColors,
        OreDropdownButton,
        OreDropdownItem,
        OrePixelIcon,
        OreScrollbar,
        OreSurface,
        resolveControlColors,
        OreStrip,
        OreStripTone,
        OreTheme,
        OreThemeBuilder,
        OreThemeController,
        OreThemeData,
        OreThemeProvider,
        OreTextField,
        OreTokens,
        OreTypography;

class Scrollbar extends StatelessWidget {
  const Scrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.trackVisibility,
    this.thickness,
    this.trackThickness,
    this.radius,
    this.interactive,
    this.notificationPredicate,
    this.scrollbarOrientation,
    this.showTrackOnHover,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final bool? trackVisibility;
  final double? thickness;
  final double? trackThickness;
  final Radius? radius;
  final bool? interactive;
  final ScrollNotificationPredicate? notificationPredicate;
  final ScrollbarOrientation? scrollbarOrientation;
  final bool? showTrackOnHover;

  @override
  Widget build(BuildContext context) {
    return OreScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility ?? true,
      trackVisibility: trackVisibility ?? true,
      thickness: thickness,
      trackThickness: trackThickness,
      child: child,
    );
  }
}

class DropdownMenuItem<T> extends StatelessWidget {
  const DropdownMenuItem({
    super.key,
    required this.value,
    required this.child,
  });

  final T value;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class DropdownButton<T> extends StatelessWidget {
  const DropdownButton({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
    this.isExpanded = false,
    this.isDense = false,
  });

  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? value;
  final Widget? hint;
  final bool isExpanded;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    final oreItems = (items ?? <DropdownMenuItem<T>>[])
        .map((item) => OreDropdownItem<T>(
              value: item.value,
              child: item.child,
            ))
        .toList();
    return OreDropdownButton<T>(
      items: oreItems,
      value: value,
      hint: hint,
      onChanged: onChanged == null ? null : (value) => onChanged?.call(value),
      size: isDense ? OreButtonSize.sm : OreButtonSize.md,
      fullWidth: isExpanded,
    );
  }
}

class DropdownButtonFormField<T> extends StatelessWidget {
  const DropdownButtonFormField({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
    this.decoration,
    this.isExpanded = false,
    this.isDense = false,
  });

  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? value;
  final Widget? hint;
  final InputDecoration? decoration;
  final bool isExpanded;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    final labelText = decoration?.labelText;
    final resolvedHint = hint ?? (labelText == null ? null : Text(labelText));
    Widget dropdown = DropdownButton<T>(
      items: items,
      value: value,
      hint: resolvedHint,
      onChanged: onChanged,
      isExpanded: isExpanded,
      isDense: isDense,
    );
    if (labelText == null) {
      return dropdown;
    }
    final ore = OreTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelText, style: ore.typography.caption),
        const SizedBox(height: OreTokens.gapXs),
        dropdown,
      ],
    );
  }
}

class DropdownButtonHideUnderline extends StatelessWidget {
  const DropdownButtonHideUnderline({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class ElevatedButton extends StatelessWidget {
  const ElevatedButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    required this.child,
    this.icon,
    this.width,
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
    double? width,
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
      width: width,
    );
  }

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final Widget child;
  final Widget? icon;
  final double? width;

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
      width: width,
      child: child,
    );
  }
}

class OutlinedButton extends StatelessWidget {
  const OutlinedButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    required this.child,
    this.icon,
    this.width,
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
    double? width,
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
      width: width,
    );
  }

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final Widget child;
  final Widget? icon;
  final double? width;

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
      width: width,
      child: child,
    );
  }
}

class TextButton extends StatelessWidget {
  const TextButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    required this.child,
    this.icon,
    this.width,
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
    double? width,
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
      width: width,
    );
  }

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final Widget child;
  final Widget? icon;
  final double? width;

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
      width: width,
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
    required this.width,
    required this.child,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final OreButtonVariant variant;
  final OreButtonSize size;
  final Widget? leading;
  final double? width;
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
      leading: leading,
      width: width,
      child: child,
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
    this.buttonWidth,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool? showSelectedIcon;
  final bool? multiSelectionEnabled;
  final bool? emptySelectionAllowed;
  final ButtonStyle? style;
  final Widget? selectedIcon;
  final double? buttonWidth;

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
      buttonWidth: buttonWidth,
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

class TextField extends StatefulWidget {
  const TextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.enabled = true,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool autofocus;

  @override
  State<TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<TextField> {
  FocusNode? _ownedFocusNode;
  bool _requestedFocus = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
  }

  @override
  void didUpdateWidget(TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (oldWidget.focusNode == null && widget.focusNode != null) {
        _ownedFocusNode?.dispose();
        _ownedFocusNode = null;
      } else if (oldWidget.focusNode != null && widget.focusNode == null) {
        _ownedFocusNode = FocusNode();
        _requestedFocus = false;
      }
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autofocus && !_requestedFocus) {
      _requestedFocus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_focusNode);
      });
    }

    final decoration = widget.decoration ?? const InputDecoration();
    final labelText = decoration.labelText;
    final errorText = decoration.errorText;
    final hintText = decoration.hintText;
    final contentPadding =
        decoration.contentPadding ?? _densePadding(decoration.isDense);

    final field = OreTextField(
      controller: widget.controller,
      focusNode: _focusNode,
      hintText: hintText,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      onEditingComplete: widget.onEditingComplete,
      onSubmitted: widget.onSubmitted,
      prefix: decoration.prefixIcon,
      suffix: decoration.suffixIcon,
      contentPadding: contentPadding,
    );

    final colors = OreTheme.of(context).colors;
    final typography = OreTheme.of(context).typography;
    final children = <Widget>[];

    if (labelText != null && labelText.isNotEmpty) {
      children.add(Text(labelText, style: typography.label));
      children.add(const SizedBox(height: OreTokens.gapXs));
    }

    children.add(field);

    if (errorText != null && errorText.isNotEmpty) {
      children.add(const SizedBox(height: OreTokens.gapXs));
      children.add(
        Text(
          errorText,
          style: typography.caption.copyWith(color: colors.danger),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  EdgeInsetsGeometry? _densePadding(bool? isDense) {
    if (isDense != true) {
      return null;
    }
    return const EdgeInsets.symmetric(
      horizontal: OreTokens.gapMd,
      vertical: OreTokens.gapXs,
    );
  }
}
