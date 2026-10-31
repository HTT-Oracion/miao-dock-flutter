import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../manga/controller/engine_controller.dart';
import '../../manga/domain/not_ready_state.dart';
import '../controller/engine_settings_controller.dart';

/// 设置屏 —— 本期先落「翻译服务」组（D-012 三层卡片 + 来源三选一 + 引擎设置）。
///
/// 其余分组（通用 / 播放·媒体 / 资源与投放 / 关于）沿用占位，随域落地补齐。
/// 左侧分组导航计数与原项目 `SET_NAV` 同构（通用 4 / 翻译 13 / 媒体 10 / 资源 2 / 关于 3）。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _sections = [
    ('general', 'settingsNavGeneral', 4),
    ('translate', 'settingsNavTranslate', 13),
    ('media', 'settingsNavMedia', 10),
    ('resource', 'settingsNavResource', 2),
    ('about', 'settingsNavAbout', 3),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(_sectionProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 16, 14),
                child: Row(
                  children: [
                    Icon(LucideIcons.settings2, size: 14, color: palette.acc),
                    const SizedBox(width: 8),
                    Text(
                      l10n.navSettings,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                  ],
                ),
              ),
              for (final (id, labelKey, count) in _sections)
                _NavItem(
                  label: _labelOf(l10n, labelKey),
                  count: count,
                  active: selected == id,
                  onTap: () => ref.read(_sectionProvider.notifier).select(id),
                ),
              const Spacer(),
            ],
          ),
        ),
        Container(width: 1, color: palette.line),
        Expanded(
          child: selected == 'translate'
              ? const _TranslateSection()
              : _PlaceholderSection(
                  label: _labelOf(l10n, selected == 'media' ? 'settingsNavMedia' : 'settingsNavAbout'),
                ),
        ),
      ],
    );
  }

  static String _labelOf(AppLocalizations l10n, String key) => switch (key) {
    'settingsNavGeneral' => l10n.settingsNavGeneral,
    'settingsNavTranslate' => l10n.settingsNavTranslate,
    'settingsNavMedia' => l10n.settingsNavMedia,
    'settingsNavResource' => l10n.settingsNavResource,
    _ => l10n.settingsNavAbout,
  };
}

class _SectionNotifier extends Notifier<String> {
  @override
  String build() => 'translate';

  void select(String id) => state = id;
}

final _sectionProvider = NotifierProvider<_SectionNotifier, String>(_SectionNotifier.new);

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.count, required this.active, required this.onTap});

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        color: active ? palette.accSoft : Colors.transparent,
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? palette.ink : palette.ink2,
              ),
            ),
            const Spacer(),
            Text('$count', style: TextStyle(fontSize: 9, color: palette.mut)),
          ],
        ),
      ),
    );
  }
}

/// 「翻译服务」组 —— D-012 三层卡片 + 来源三选一 + 引擎设置。
class _TranslateSection extends ConsumerWidget {
  const _TranslateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsNavTranslate,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(height: 4),
          Text(l10n.settingsBlurbTranslate, style: TextStyle(fontSize: 10.5, color: palette.mut)),
          const SizedBox(height: 18),
          const _ServiceCard(),
          const SizedBox(height: 18),
          _SectionTitle(title: l10n.settingsSectionSource, head: l10n.settingsSectionSourceHead),
          const _SourceRow(),
          const SizedBox(height: 16),
          _SectionTitle(title: l10n.settingsSectionPairing, head: l10n.settingsSectionPairingHead),
          const _PairingRows(),
          const SizedBox(height: 16),
          _SectionTitle(title: l10n.settingsSectionInference, head: l10n.settingsSectionInferenceHead),
          const _InferenceRows(),
        ],
      ),
    );
  }
}

/// 服务卡片（D-012）—— 引擎组状态 + 启停（共用开关）。
class _ServiceCard extends ConsumerWidget {
  const _ServiceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(notReadyViewProvider);
    final engineRunning = view.engine.isReady;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: engineRunning ? palette.good : palette.warn, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      engineRunning ? l10n.svcEngineReady : l10n.svcEngineOff,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.ink),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: palette.good.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                      ),
                      child: Text(l10n.svcCardService, style: TextStyle(fontSize: 8.5, color: palette.good)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${l10n.nrLayerEngine} · ${switch (view.source) {
                    TranslateSource.local => l10n.sourceLocal,
                    TranslateSource.llm => l10n.sourceLlm,
                    TranslateSource.remote => l10n.sourceRemote,
                  }}',
                  style: TextStyle(fontSize: 10.5, color: palette.ink2),
                ),
              ],
            ),
          ),
          // 启 / 停：引擎组的共用开关（D-012），一次点击拉起 / 停止两个进程
          FilledButton(
            onPressed: () {
              final notifier = ref.read(engineStateProvider.notifier);
              engineRunning ? notifier.stop() : notifier.start();
            },
            style: FilledButton.styleFrom(
              backgroundColor: engineRunning ? palette.hi : palette.acc,
              foregroundColor: engineRunning ? palette.ink2 : palette.onAcc,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
            child: Text(engineRunning ? l10n.svcStop : l10n.svcStart),
          ),
        ],
      ),
    );
  }
}

/// 小节标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.head});

  final String title;
  final String head;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(head, style: TextStyle(fontSize: 9.5, color: palette.mut)),
          ),
        ],
      ),
    );
  }
}

/// 设置行（标签 + 说明 + 控件）。
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.why, this.control, this.trailing});

  final String label;
  final String why;
  final Widget? control;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // 尾件二选一：文字（trailing）优先于控件（control）；null = 都没有。
    final trailingText = trailing;
    final Widget? tail = trailingText != null
        ? Text(trailingText, style: TextStyle(fontSize: 11, color: palette.ink2))
        : control;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.ink),
                ),
                const SizedBox(height: 2),
                Text(why, style: TextStyle(fontSize: 9.5, height: 1.5, color: palette.mut)),
              ],
            ),
          ),
          ?tail,
        ],
      ),
    );
  }
}

/// 来源三选一（D-012）。
class _SourceRow extends ConsumerWidget {
  const _SourceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(translateSourceProvider);
    final notifier = ref.read(translateSourceProvider.notifier);

    return _SettingRow(
      label: l10n.settingSourceLabel,
      why: l10n.settingSourceWhy,
      control: SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'local',
            label: Text(l10n.sourceLocal, style: const TextStyle(fontSize: 10)),
          ),
          ButtonSegment(
            value: 'llm',
            label: Text(l10n.sourceLlm, style: const TextStyle(fontSize: 10)),
          ),
          ButtonSegment(
            value: 'remote',
            label: Text(l10n.sourceRemote, style: const TextStyle(fontSize: 10)),
          ),
        ],
        selected: {current.wire},
        onSelectionChanged: (s) {
          // 🔴 移动端切到需要本机运行时的来源会被 controller 拒绝（D-012）。
          notifier.set(TranslateSource.parse(s.first));
        },
      ),
    );
  }
}

/// 服务与配对行。
class _PairingRows extends ConsumerWidget {
  const _PairingRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final autoStart = ref.watch(_autoStartProvider);
    return Column(
      children: [
        _SettingRow(
          label: l10n.svcAutoStart,
          why: l10n.svcAutoStartWhy,
          control: Switch(value: autoStart, onChanged: (v) => ref.read(_autoStartProvider.notifier).set(v)),
        ),
        _SettingRow(
          label: l10n.svcAutoStartEngine,
          why: l10n.svcAutoStartEngineWhy,
          control: Switch(value: true, onChanged: (_) {}),
        ),
      ],
    );
  }
}

final _autoStartProvider = NotifierProvider<_AutoStartNotifier, bool>(_AutoStartNotifier.new);

class _AutoStartNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool v) => state = v;
}

/// 推理引擎行（C2 数据驱动）。
class _InferenceRows extends ConsumerWidget {
  const _InferenceRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final settings = ref.watch(engineSettingsProvider);
    final notifier = ref.read(engineSettingsProvider.notifier);

    return Column(
      children: [
        _SettingRow(label: l10n.settingTierLabel, why: l10n.settingTierWhy, trailing: settings.tier),
        _SettingRow(label: l10n.settingAccelLabel, why: l10n.settingAccelWhy, trailing: settings.accel),
        _SettingRow(
          label: l10n.settingIdleLlmLabel,
          why: l10n.svcIdleUnloadWhy,
          control: DropdownButton<int>(
            value: settings.idleUnloadMinutes,
            items: [
              for (final m in const [0, 5, 15, 30, 60])
                DropdownMenuItem(
                  value: m,
                  child: Text(l10n.settingMinutes(m), style: const TextStyle(fontSize: 11)),
                ),
            ],
            // C2 契约：改档位 / 后端需重启；卸载阈值立即生效。
            onChanged: (m) {
              if (m != null) notifier.save(idleUnloadMinutes: m);
            },
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 11, color: palette.ink2),
          ),
        ),
      ],
    );
  }
}

/// 占位分组。
class _PlaceholderSection extends StatelessWidget {
  const _PlaceholderSection({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Text(label, style: TextStyle(fontSize: 13, color: palette.mut)),
    );
  }
}
