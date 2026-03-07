import 'package:flutter/material.dart';

import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';
import '../widgets/ore_button.dart';
import '../widgets/ore_checkbox.dart';
import '../widgets/ore_choice_buttons.dart';
import '../widgets/ore_choice_description.dart';
import '../widgets/ore_choice_title.dart';
import '../widgets/ore_card.dart';
import '../widgets/ore_dropdown_button.dart';
import '../widgets/ore_loading_indicator.dart';
import '../widgets/ore_pixel_icon.dart';
import '../widgets/ore_scrollbar.dart';
import '../widgets/ore_slider.dart';
import '../widgets/ore_strip.dart';
import '../widgets/ore_switch.dart';
import '../widgets/ore_theme_mode_switch.dart';
import '../widgets/ore_text_field.dart';

class OreShowcaseApp extends StatefulWidget {
  const OreShowcaseApp({super.key});

  @override
  State<OreShowcaseApp> createState() => _OreShowcaseAppState();
}

class _OreShowcaseAppState extends State<OreShowcaseApp> {
  late final OreThemeController _controller = OreThemeController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OreThemeBuilder(
      controller: _controller,
      builder: (context, data, brightness) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: brightness,
            extensions: [data],
          ),
          home: const OreShowcasePage(),
        );
      },
    );
  }
}

class OreShowcasePage extends StatefulWidget {
  const OreShowcasePage({super.key});

  @override
  State<OreShowcasePage> createState() => _OreShowcasePageState();
}

class _OreShowcasePageState extends State<OreShowcasePage> {
  bool _checked = true;
  bool _toggled = true;
  bool? _tri;
  int _difficulty = 0;
  double _slider = 0.6;
  int _choice = 0;
  OreChoiceDock _choiceDock = OreChoiceDock.bottom;
  String _dropdownValue = '选项一';
  final TextEditingController _controller =
      TextEditingController(text: 'Ore UI');
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _buttonWidthController =
      TextEditingController(text: '40');
  double? _buttonWidthUnits = 40;

  static const List<OreDropdownItem<String>> _dropdownItems = [
    OreDropdownItem(value: '选项一', child: Text('选项一')),
    OreDropdownItem(value: '选项二', child: Text('选项二')),
    OreDropdownItem(value: '选项三', child: Text('选项三')),
  ];
  static const List<Widget> _difficultyItems = [
    Text('和平'),
    Text('简单'),
    Text('一般'),
    Text('困难'),
  ];
  static const List<Widget> _choiceItems = [
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrePixelIcon(icon: Icons.public, size: 16),
        SizedBox(width: OreTokens.gapXs),
        Text('选项一'),
      ],
    ),
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrePixelIcon(icon: Icons.explore, size: 16),
        SizedBox(width: OreTokens.gapXs),
        Text('选项二'),
      ],
    ),
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrePixelIcon(icon: Icons.extension, size: 16),
        SizedBox(width: OreTokens.gapXs),
        Text('选项三'),
      ],
    ),
  ];
  static const List<Widget> _difficultyDescriptions = [
    Text('没有敌对生物，只会生成一些中立生物。饥饿条不会消耗，且生命值会随时间回复。'),
    Text('会生成敌对生物，但其造成的伤害较少。饥饿条会消耗，且生命值降低至5颗心。'),
    Text('会生成敌对生物，造成正常伤害。饥饿条会消耗，且生命值降低至一半颗心。'),
    Text('会生成敌对生物，且其造成的伤害增加。饥饿条会消耗，且生命值降低为零。'),
  ];
  static const List<Widget> _choiceDockItems = [
    Text('贴底部'),
    Text('贴顶部'),
    Text('贴左侧'),
    Text('贴右侧'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _pageScrollController.dispose();
    _scrollController.dispose();
    _buttonWidthController.dispose();
    super.dispose();
  }

  void _updateButtonWidth(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _buttonWidthUnits = null);
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return;
    setState(() => _buttonWidthUnits = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final ore = OreTheme.of(context);
    final colors = ore.colors;
    final buttonWidth = _buttonWidthUnits == null
        ? null
        : _buttonWidthUnits! * ore.borderWidth;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: OreScrollbar(
          controller: _pageScrollController,
          child: SingleChildScrollView(
            controller: _pageScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              OreStrip(
                child: Padding(
                  padding: const EdgeInsets.all(OreTokens.gapLg),
                  child: DefaultTextStyle.merge(
                    style: ore.typography.body.copyWith(
                      color: colors.textPrimary,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'Ore UI Showcase',
                                style: ore.typography.title,
                              ),
                            ),
                            const SizedBox(width: OreTokens.gapSm),
                            Text(
                              '深色模式',
                              style: ore.typography.caption,
                            ),
                            const SizedBox(width: OreTokens.gapSm),
                            const OreThemeModeSwitch(),
                          ],
                        ),
                        const SizedBox(height: OreTokens.gapLg),
                        Text('Buttons', style: ore.typography.label),
                        const SizedBox(height: OreTokens.gapSm),
                        Wrap(
                          spacing: OreTokens.gapSm,
                          runSpacing: OreTokens.gapSm,
                          children: [
                            OreButton(
                              onPressed: () {},
                              child: const Text('Normal'),
                            ),
                            OreButton(
                              variant: OreButtonVariant.primary,
                              onPressed: () {},
                              child: const Text('Confirm'),
                            ),
                            OreButton(
                              variant: OreButtonVariant.danger,
                              onPressed: () {},
                              child: const Text('Delete'),
                            ),
                            const OreButton(
                              onPressed: null,
                              child: Text('Disabled'),
                            ),
                          ],
                        ),
                        const SizedBox(height: OreTokens.gapMd),
                        Text('Icon Buttons', style: ore.typography.label),
                        const SizedBox(height: OreTokens.gapSm),
                        Wrap(
                          spacing: OreTokens.gapSm,
                          runSpacing: OreTokens.gapSm,
                          children: [
                            OreButton(
                              onPressed: () {},
                              leading:
                                  const OrePixelIcon(icon: Icons.star, size: 16),
                              child: const Text('收藏'),
                            ),
                            OreButton(
                              variant: OreButtonVariant.primary,
                              onPressed: () {},
                              leading: const OrePixelIcon(icon: Icons.add, size: 16),
                              child: const Text('创建'),
                            ),
                          ],
                        ),
                        const SizedBox(height: OreTokens.gapMd),
                        Text('Fixed Width', style: ore.typography.label),
                        const SizedBox(height: OreTokens.gapSm),
                        Wrap(
                          spacing: OreTokens.gapSm,
                          runSpacing: OreTokens.gapSm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OreButton(
                              width: buttonWidth,
                              onPressed: () {},
                              child: const Text('固定宽度'),
                            ),
                            SizedBox(
                              width: OreTokens.controlHeightMd * 2,
                              child: OreTextField(
                                controller: _buttonWidthController,
                                hintText: '宽度(单位)',
                                keyboardType: TextInputType.number,
                                onChanged: _updateButtonWidth,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              OreStrip(
                child: Padding(
                  padding: const EdgeInsets.all(OreTokens.gapLg),
                  child: DefaultTextStyle.merge(
                    style: ore.typography.body.copyWith(
                      color: colors.textPrimary,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Form', style: ore.typography.label),
                        const SizedBox(height: OreTokens.gapSm),
                        OreTextField(
                          controller: _controller,
                          hintText: '输入内容',
                          onChanged: (_) {},
                        ),
                        const SizedBox(height: OreTokens.gapMd),
                        OreTextField(
                          enabled: false,
                          hintText: '禁用输入框',
                        ),
                        const SizedBox(height: OreTokens.gapMd),
                        OreSlider(
                          value: _slider,
                          onChanged: (value) =>
                              setState(() => _slider = value),
                        ),
                        const SizedBox(height: OreTokens.gapMd),
                        OreDropdownButton<String>(
                          items: _dropdownItems,
                          value: _dropdownValue,
                          onChanged: (value) =>
                              setState(() => _dropdownValue = value),
                        ),
                        const SizedBox(height: OreTokens.gapMd),
                        Text('Scrollbar', style: ore.typography.label),
                        const SizedBox(height: OreTokens.gapSm),
                        OreCard(
                          padding: EdgeInsets.zero,
                          child: SizedBox(
                            height: OreTokens.controlHeightLg * 4,
                            child: OreScrollbar(
                              controller: _scrollController,
                              child: ListView.separated(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  OreTokens.gapSm,
                                  OreTokens.gapSm,
                                  OreTokens.gapXl,
                                  OreTokens.gapSm,
                                ),
                                itemCount: 18,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: OreTokens.gapXs),
                                itemBuilder: (context, index) => Text(
                                  '条目 ${index + 1}',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              OreStrip(
                child: Padding(
                  padding: const EdgeInsets.all(OreTokens.gapLg),
                  child: DefaultTextStyle.merge(
                    style: ore.typography.body.copyWith(
                      color: colors.textPrimary,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Toggles', style: ore.typography.label),
                        const SizedBox(height: OreTokens.gapSm),
                        Text('Choice Layout', style: ore.typography.caption),
                        const SizedBox(height: OreTokens.gapXs),
                        OreChoiceButtons(
                          items: _choiceDockItems,
                          selectedIndex: _choiceDock.index,
                          onChanged: (value) => setState(() =>
                              _choiceDock = OreChoiceDock.values[value]),
                          size: OreButtonSize.sm,
                        ),
                        const SizedBox(height: OreTokens.gapSm),
                        OreChoiceButtons(
                          items: _choiceItems,
                          selectedIndex: _choice,
                          onChanged: (value) =>
                              setState(() => _choice = value),
                          dock: _choiceDock,
                        ),
                        const SizedBox(height: OreTokens.gapSm),
                        Wrap(
                          spacing: OreTokens.gapLg,
                          runSpacing: OreTokens.gapSm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OreCheckbox(
                              value: _checked,
                              onChanged: (value) =>
                                  setState(() => _checked = value ?? false),
                              label: const Text('Checked'),
                            ),
                            OreCheckbox(
                              value: _tri,
                              tristate: true,
                              onChanged: (value) => setState(() => _tri = value),
                              label: const Text('Tri-state'),
                            ),
                            OreSwitch(
                              value: _toggled,
                              onChanged: (value) =>
                                  setState(() => _toggled = value),
                            ),
                          ],
                        ),
                        const SizedBox(height: OreTokens.gapMd),
                        Text('Loading', style: ore.typography.label),
                        const SizedBox(height: OreTokens.gapSm),
                        Wrap(
                          spacing: OreTokens.gapMd,
                          runSpacing: OreTokens.gapSm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: const [
                            OreLoadingIndicator(),
                            OreLoadingIndicator(tone: OreLoadingTone.dark),
                            OreLoadingIndicator(tone: OreLoadingTone.light),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              OreStrip(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OreTokens.gapLg,
                    vertical: OreTokens.gapSm,
                  ),
                  child: DefaultTextStyle.merge(
                    style: ore.typography.body.copyWith(
                      color: colors.textPrimary,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const OreChoiceTitle(child: Text('难度')),
                        const SizedBox(height: OreTokens.gapSm),
                        OreChoiceButtons(
                          items: _difficultyItems,
                          selectedIndex: _difficulty,
                          onChanged: (value) =>
                              setState(() => _difficulty = value),
                        ),
                        const SizedBox(height: OreTokens.gapSm),
                        OreChoiceDescription(
                          items: _difficultyDescriptions,
                          selectedIndex: _difficulty,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
