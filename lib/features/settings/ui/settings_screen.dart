import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/storage/paths.dart';
import '../../../core/storage/shell_prefs.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_select.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/widgets/log_box.dart';
import '../../../shared/widgets/setting_row.dart';
import '../../manga/controller/engine_controller.dart';
import '../../manga/controller/engine_install_controller.dart';
import '../../manga/controller/engine_ready_controller.dart';
import '../../manga/domain/not_ready_state.dart';
import '../controller/engine_dir_controller.dart';
import '../controller/engine_settings_controller.dart';
import 'engine_parts_view.dart';

/// 设置屏 —— 按 `ver1.0` 的「通用 / 翻译服务」两组落地（D-040）。
///
/// ## 与设计稿的冲突，一律以项目为准
/// | 设计稿 | 项目事实 | 采用 |
/// |---|---|---|
/// | 服务卡片写死「服务运行中」绿点 | D-012 已删除该标识（服务常驻后无信息量） | 显示**引擎就绪度** |
/// | 「加速后端」含 DirectML | llama.cpp 无该构建（实测 b11417） | 只给 自动 / CPU / Vulkan / CUDA 12.4 |
/// | 模型目录 `…\runtimes\…\models-store` | D-031 模型在 `<engine>/src/models` | 用真实路径 |
/// | 落盘根目录 `D:\MiaoDock\library` | D-015 漫画库在 `~/Pictures/MiaoDock Mangas` | 用真实路径 |
///
/// ## 设计稿漏掉、本项目已有的能力（补进来）
/// 引擎目录 / 部件表 / 校验 / 重新检查 / 导入本地 / 诊断输出 —— 设计稿没有，但项目已实现。
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
          width: 208,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 12, 12),
                child: Row(
                  children: [
                    Icon(LucideIcons.settings2, size: 13, color: palette.acc),
                    const SizedBox(width: 7),
                    Text(
                      l10n.navSettings,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.ink),
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
              _NavItem(
                label: l10n.settingsBackHome,
                icon: LucideIcons.arrowLeft,
                active: false,
                onTap: () => context.go('/manga/queue'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        Container(width: 1, color: palette.line),
        Expanded(
          child: switch (selected) {
            'general' => const _GeneralSection(),
            'translate' => const _TranslateSection(),
            _ => _PlaceholderSection(
              label: _labelOf(l10n, selected == 'media' ? 'settingsNavMedia' : 'settingsNavAbout'),
            ),
          },
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
  String build() => 'general';

  void select(String id) => state = id;
}

final _sectionProvider = NotifierProvider<_SectionNotifier, String>(_SectionNotifier.new);

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.active, required this.onTap, this.count, this.icon});

  final String label;
  final int? count;
  final bool active;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? palette.accSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: active ? palette.acc : palette.mut),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? palette.ink : palette.ink2,
              ),
            ),
            const Spacer(),
            if (count != null) Text('$count', style: TextStyle(fontSize: 8.5, color: palette.mut)),
          ],
        ),
      ),
    );
  }
}

/// 页面标题（design.html `h2` + `.blurb`）。
class _Head extends StatelessWidget {
  const _Head({required this.title, required this.blurb});

  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink),
        ),
        const SizedBox(height: 3),
        Text(blurb, style: TextStyle(fontSize: 9.5, color: palette.mut)),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ── 通用 ────────────────────────────────────────────────────────────────

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final labels = ref.watch(sidebarLabelsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(title: l10n.settingsNavGeneral, blurb: l10n.settingsBlurbGeneral),
          SettingRow(
            label: l10n.settingDarkMode,
            why: l10n.settingDarkModeWhy,
            def: themeMode == ThemeMode.dark ? l10n.settingDark : l10n.settingLight,
            control: AppSwitch(
              value: themeMode == ThemeMode.dark,
              onChanged: (v) => ref.read(themeModeProvider.notifier).set(v ? ThemeMode.dark : ThemeMode.light),
            ),
          ),
          SettingRow(
            label: l10n.settingCloseBehavior,
            why: l10n.settingTrayNotWired,
            def: l10n.settingCloseToTray,
            dimmed: true,
            control: AppSelect<String>(
              value: 'tray',
              enabled: false,
              items: [(('tray'), l10n.settingCloseToTray), (('quit'), l10n.settingCloseQuit)],
              onChanged: null,
            ),
          ),
          SettingRow(
            label: l10n.settingSpecCheck,
            why: l10n.settingSpecNotWired,
            dimmed: true,
            control: FilledButton(
              onPressed: null,
              style: _primaryStyle(AppPalette.of(context)),
              child: Text(l10n.settingSpecCheckRun, style: const TextStyle(fontSize: 9.5)),
            ),
          ),
          SettingRow(
            label: l10n.settingSidebarLabels,
            why: l10n.settingSidebarLabelsWhy,
            def: l10n.settingSidebarLabelsShow,
            control: AppSwitch(value: labels, onChanged: (v) => ref.read(sidebarLabelsProvider.notifier).set(v)),
          ),
        ],
      ),
    );
  }
}

// ── 翻译服务 ────────────────────────────────────────────────────────────

class _TranslateSection extends ConsumerWidget {
  const _TranslateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(title: l10n.settingsNavTranslate, blurb: l10n.settingsBlurbTranslate),

          // 三层状态条（项目口径 D-012，设计稿没有）：服务常驻 / 引擎共用开关 / 来源。
          const _LayerStrip(),
          const SizedBox(height: 12),

          // 设计稿没有、项目已有的能力：引擎目录 + 部件表 + 校验 + 导入。
          const EnginePartsSection(),
          const SizedBox(height: 12),

          const _ServiceCard(),

          SettingSubTitle(l10n.settingsSectionSource),
          const _SourceRow(),

          SettingSubTitle(l10n.settingsSectionPairing),
          const _PairingRows(),

          SettingSubTitle(l10n.settingsSectionInference),
          const _InferenceRows(),

          SettingSubTitle(l10n.settingsSectionModels),
          const _ModelRows(),

          const _DiagOutput(),
        ],
      ),
    );
  }
}

/// 三层状态条（D-012）。设计稿的设置页没有它，但「服务常驻」是项目里最容易被误解的事实。
class _LayerStrip extends ConsumerWidget {
  const _LayerStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final source = ref.watch(translateSourceProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Column(
        children: [
          _LayerRow(dot: palette.good, title: l10n.nrLayerService, sub: l10n.nrLayerServiceSub),
          const SizedBox(height: 6),
          _LayerRow(dot: palette.acc, title: l10n.nrLayerEngine, sub: l10n.nrLayerEngineSub),
          const SizedBox(height: 6),
          _LayerRow(
            dot: palette.warn,
            title: l10n.nrLayerSource,
            sub: switch (source) {
              TranslateSource.local => l10n.sourceLocal,
              TranslateSource.llm => l10n.sourceLlm,
              TranslateSource.remote => l10n.sourceRemote,
            },
          ),
        ],
      ),
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({required this.dot, required this.title, required this.sub});

  final Color dot;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.ink),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(sub, style: TextStyle(fontSize: 9, color: palette.mut)),
        ),
      ],
    );
  }
}

/// 服务卡片（design.html `.svccard`：1.5px 主色边框）。
///
/// 内容按项目口径：**不写「服务运行中」**（D-012），显示引擎就绪度与启停。
class _ServiceCard extends ConsumerWidget {
  const _ServiceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(notReadyViewProvider);
    final install = ref.watch(engineInstallProvider);
    final running = view.engine.isReady;

    final subtitle = switch ((install.running, view.state)) {
      (true, _) => l10n.nrTitleDownloading,
      (_, NotReadyState.degraded) => l10n.nrTitleDegraded,
      (_, NotReadyState.failed) => l10n.nrTitleFailed,
      _ => running ? l10n.svcEngineReady : l10n.svcEngineOff,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.acc, width: 1.5),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: running ? palette.good : palette.warn, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.ink),
                    ),
                    const SizedBox(width: 8),
                    _Pill(text: l10n.svcCardLocalService),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${l10n.nrLayerEngine} · ${_sourceLabel(l10n, view.source)}',
                  style: TextStyle(fontSize: 10, color: palette.ink2),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () {
              final n = ref.read(engineStateProvider.notifier);
              running ? n.stop() : n.start();
            },
            style: _primaryStyle(palette),
            child: Text(running ? l10n.svcStop : l10n.svcStart, style: const TextStyle(fontSize: 9.5)),
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(AppLocalizations l10n, TranslateSource s) => switch (s) {
    TranslateSource.local => l10n.sourceLocal,
    TranslateSource.llm => l10n.sourceLlm,
    TranslateSource.remote => l10n.sourceRemote,
  };
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: palette.good.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
      ),
      child: Text(text, style: TextStyle(fontSize: 8.5, color: palette.good)),
    );
  }
}

/// 主按钮样式（`.btn.pri` + 卡片内联 34/18/11）。
ButtonStyle _primaryStyle(AppPalette palette) => FilledButton.styleFrom(
  backgroundColor: palette.acc,
  foregroundColor: palette.onAcc,
  minimumSize: const Size(0, 34),
  padding: const EdgeInsets.symmetric(horizontal: 18),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppMetrics.radiusButton)),
  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
);

class _SourceRow extends ConsumerWidget {
  const _SourceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(translateSourceProvider);
    return SettingRow(
      label: l10n.settingSourceLabel,
      why: l10n.settingSourceWhy,
      def: _label(l10n, current),
      control: AppSelect<TranslateSource>(
        value: current,
        items: [
          (TranslateSource.local, l10n.sourceLocal),
          (TranslateSource.llm, l10n.sourceLlm),
          (TranslateSource.remote, l10n.sourceRemote),
        ],
        onChanged: (v) => ref.read(translateSourceProvider.notifier).set(v),
      ),
    );
  }

  static String _label(AppLocalizations l10n, TranslateSource s) => switch (s) {
    TranslateSource.local => l10n.sourceLocal,
    TranslateSource.llm => l10n.sourceLlm,
    TranslateSource.remote => l10n.sourceRemote,
  };
}

class _PairingRows extends ConsumerWidget {
  const _PairingRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final autoService = ref.watch(_autoStartServiceProvider);
    final autoEngine = ref.watch(_autoStartEngineProvider);

    return Column(
      children: [
        SettingRow(
          label: l10n.svcAutoStart,
          why: l10n.svcAutoStartWhy,
          control: AppSwitch(value: autoService, onChanged: (v) => ref.read(_autoStartServiceProvider.notifier).set(v)),
        ),
        SettingRow(
          label: l10n.svcAutoStartEngine,
          why: l10n.svcAutoStartEngineWhy,
          control: AppSwitch(value: autoEngine, onChanged: (v) => ref.read(_autoStartEngineProvider.notifier).set(v)),
        ),
        SettingRow(
          label: l10n.settingLibraryDirLabel,
          why: l10n.settingLibraryDirWhy,
          control: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.line2),
              borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            ),
            child: Text(
              mangaLibraryDir(),
              style: TextStyle(fontSize: 9, color: palette.ink2, fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}

final _autoStartServiceProvider = NotifierProvider<_AutoStartService, bool>(_AutoStartService.new);

class _AutoStartService extends Notifier<bool> {
  @override
  bool build() => readAutoStartService();

  void set(bool v) {
    state = v;
    persistAutoStartService(v);
  }
}

final _autoStartEngineProvider = NotifierProvider<_AutoStartEngine, bool>(_AutoStartEngine.new);

class _AutoStartEngine extends Notifier<bool> {
  @override
  bool build() => readAutoStartEngine();

  void set(bool v) {
    state = v;
    persistAutoStartEngine(v);
  }
}

class _InferenceRows extends ConsumerWidget {
  const _InferenceRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(engineSettingsProvider);
    final n = ref.read(engineSettingsProvider.notifier);
    const minutes = [0, 5, 15, 30, 60];

    return Column(
      children: [
        SettingRow(
          label: l10n.settingDirectionLabel,
          why: l10n.settingDirectionWhy,
          def: l10n.settingDirJaZh,
          dimmed: true,
          control: AppSelect<String>(
            value: 'ja-zh',
            enabled: false,
            items: [('ja-zh', l10n.settingDirJaZh)],
            onChanged: null,
          ),
        ),
        SettingRow(
          label: l10n.settingTierLabel,
          why: l10n.settingTierWhy,
          def: l10n.settingTierByHw,
          control: AppSelect<String>(
            value: s.tier,
            items: [
              ('auto', l10n.settingTierByHw),
              ('lite', l10n.settingTierLite),
              ('standard', l10n.settingTierStandard),
              ('high', l10n.settingTierHigh),
            ],
            onChanged: (v) => n.save(tier: v),
          ),
        ),
        SettingRow(
          label: l10n.settingAccelLabel,
          why: l10n.settingAccelWhy,
          def: l10n.settingAuto,
          control: AppSelect<String>(
            value: s.accel,
            items: [
              ('auto', l10n.settingAuto),
              ('cpu', l10n.engineBackendCpu),
              ('vulkan', l10n.engineBackendVulkan),
              ('cuda-12.4', l10n.engineBackendCuda),
            ],
            onChanged: (v) => n.save(accel: v),
          ),
        ),
        SettingRow(
          label: l10n.settingIdleLlmLabel,
          why: l10n.svcIdleUnloadWhy,
          control: AppSelect<int>(
            value: s.idleUnloadMinutes,
            items: [for (final m in minutes) (m, l10n.settingMinutes(m))],
            onChanged: (v) => n.save(idleUnloadMinutes: v),
          ),
        ),
        SettingRow(
          label: l10n.settingIdleVisualLabel,
          why: l10n.svcIdleUnloadWhy,
          control: AppSelect<int>(
            value: s.visualIdleUnloadMinutes,
            items: [for (final m in minutes) (m, l10n.settingMinutes(m))],
            onChanged: (v) => n.save(visualIdleUnloadMinutes: v),
          ),
        ),
      ],
    );
  }
}

class _ModelRows extends ConsumerWidget {
  const _ModelRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final dir = ref.watch(engineRootProvider);

    return Column(
      children: [
        SettingRow(
          label: l10n.settingModelsDirLabel,
          why: l10n.settingModelDirWhy,
          control: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.line2),
              borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            ),
            child: Text(
              engineModelsDir(dir),
              style: TextStyle(fontSize: 9, color: palette.ink2, fontFamily: 'monospace'),
            ),
          ),
        ),
        SettingRow(
          label: l10n.settingVerifyLabel,
          why: l10n.settingSectionModelHead,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: () => ref.read(engineInspectionProvider.notifier).run(),
                style: _ghostStyle(palette),
                child: Text(l10n.settingModelVerify, style: const TextStyle(fontSize: 9.5)),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () => ref.read(enginePresenceProvider.notifier).refresh(),
                style: _ghostStyle(palette),
                child: Text(l10n.engineRecheck, style: const TextStyle(fontSize: 9.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

ButtonStyle _ghostStyle(AppPalette palette) => OutlinedButton.styleFrom(
  foregroundColor: palette.ink2,
  minimumSize: const Size(0, 28),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  side: BorderSide(color: palette.line2),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppMetrics.radiusButton)),
  textStyle: const TextStyle(fontSize: 9.5),
);

/// 诊断输出（design.html `.diag`）—— 复用日志组件，hover 可复制/导出。
class _DiagOutput extends ConsumerWidget {
  const _DiagOutput();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final install = ref.watch(engineInstallProvider);
    final lines = install.logs.isEmpty ? [l10n.engineNotChecked] : install.logs;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingSubTitle(l10n.settingDiagTitle),
          LogBox(lines: lines, title: l10n.settingDiagTitle, maxHeight: 150),
        ],
      ),
    );
  }
}

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
