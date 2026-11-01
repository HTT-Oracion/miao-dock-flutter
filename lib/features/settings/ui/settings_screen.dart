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
import '../../../shared/widgets/toast.dart';
import '../../manga/controller/engine_controller.dart';
import '../../manga/controller/engine_install_controller.dart';
import '../../manga/controller/engine_ready_controller.dart';
import '../../manga/controller/queue_controller.dart';
import '../../manga/domain/not_ready_state.dart';
import '../../manga/controller/remote_controller.dart';
import '../controller/credential_controller.dart';
import '../../manga/domain/platform_caps.dart';
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

class _NavItem extends StatefulWidget {
  const _NavItem({required this.label, required this.active, required this.onTap, this.count, this.icon});

  final String label;
  final int? count;
  final bool active;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final active = widget.active;
    final icon = widget.icon;
    final label = widget.label;
    final count = widget.count;
    final onTap = widget.onTap;
    // hover 与高亮**共用同一个 Container**：InkWell 放进内层，
    // 否则水波纹会覆盖到外边距，hover 区域比高亮大一圈（用户实测指出）。
    return MouseRegion(
      // 设置页导航也是可点项：hover 变手型（用户要求）。
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: active ? palette.accSoft : (_hover ? palette.card : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: InkWell(
          onTap: onTap,
          onHover: (v) => setState(() => _hover = v),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
    final source = ref.watch(translateSourceProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(title: l10n.settingsNavTranslate, blurb: l10n.settingsBlurbTranslate),

          if (!supportsLocalEngine) ...[
            // Web / 移动端：本机不跑引擎，引擎相关的设置**整块不出现**。
            const _RemoteOnlyNote(),
            SettingSubTitle(l10n.settingsSectionSource),
            const _SourceRow(),
            const _RemoteSection(),
          ] else ...[
            // 「模型」放在首部：引擎目录 / 启动服务 / 校验 / 导入 —— 能不能翻译的前提。
            SettingSubTitle(l10n.settingsSectionModels),
            const _ServiceCard(),
            const SizedBox(height: 6),
            const EnginePartsSection(),
            const SizedBox(height: 8),
            const _TranslateLogBox(),

            SettingSubTitle(l10n.settingsSectionSource),
            const _SourceRow(),
            if (source == TranslateSource.remote) const _RemoteSection(),
            if (source == TranslateSource.llm) const _LlmCredentialSection(),

            SettingSubTitle(l10n.settingsSectionPairing),
            const _PairingRows(),

            SettingSubTitle(l10n.settingsSectionInference),
            const _InferenceRows(),
          ],
        ],
      ),
    );
  }
}

/// 翻译日志（D-075）：放在「模型」区，任务事件与逐页失败原因都在这里。
///
/// 与诊断输出（装配日志）分开：那条是「引擎装没装好」，这条是「翻译跑得怎么样」。
class _TranslateLogBox extends ConsumerWidget {
  const _TranslateLogBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lines = ref.watch(translateLogProvider).value ?? const <String>[];
    return LogBox(
      title: l10n.translateLogTitle,
      lines: lines.isEmpty ? [l10n.translateLogEmpty] : lines,
      maxHeight: 140,
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(notReadyViewProvider);
    final install = ref.watch(engineInstallProvider);
    // 🔴 必须直接看 engineStateProvider：`notReadyViewProvider` 传的是 `status: null`，
    // 其 `engine` 恒为 off —— 用它判断会导致按钮永远没有 loading 态。
    final engineState = ref.watch(engineStateProvider);
    final running = engineState.isReady;

    // 启动前置条件（D-062）：**装配齐全 且 校验通过**才允许点启动。
    // 没装好就点启动，只会得到一个语焉不详的失败；不如直接禁用并说明原因。
    final installed = ref.watch(enginePresenceProvider).value == EnginePresence.complete;
    final verified = ref.watch(engineInspectionProvider).value?.ok ?? false;
    final starting = engineState == EngineRuntimeState.starting;
    final startError = ref.watch(engineStartErrorProvider);
    final canStart = installed && verified && !starting;
    final blockedReason = !installed
        ? l10n.svcStartNeedInstall
        : !verified
        ? l10n.svcStartNeedVerify
        : null;

    final subtitle = switch ((install.running, view.state)) {
      (true, _) => l10n.nrTitleDownloading,
      (_, NotReadyState.degraded) => l10n.nrTitleDegraded,
      (_, NotReadyState.failed) => l10n.nrTitleFailed,
      _ => running ? l10n.svcEngineReady : l10n.svcEngineOff,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      // 不做边框高亮：这只是一张普通卡片，主色描边会让它看起来像「正在报警」。
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
      ),
      child: Row(
        children: [
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
                    const SizedBox(width: 6),
                    // 状态圆点：放在文字右侧、尺寸收小（8px）。
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: running ? palette.good : palette.warn, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    _Pill(text: l10n.svcCardLocalService),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  startError != null
                      ? '${l10n.svcStartFailed}：$startError'
                      : blockedReason ?? '${l10n.nrLayerEngine} · ${_sourceLabel(l10n, view.source)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: startError != null ? palette.bad : (blockedReason == null ? palette.ink2 : palette.warn),
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            // 运行中可停止；未启动时必须满足前置条件且不在启动中。
            onPressed: running
                ? () => ref.read(engineStateProvider.notifier).stop()
                : (canStart
                      ? () async {
                          await ref.read(engineStateProvider.notifier).start();
                          if (!context.mounted) return;
                          final err = ref.read(engineStartErrorProvider);
                          showAppToast(
                            context,
                            err == null ? l10n.svcStartOk : '${l10n.svcStartFailed}：$err',
                            tone: err == null ? ToastTone.good : ToastTone.bad,
                          );
                        }
                      : null),
            style: _primaryStyle(palette),
            child: starting
                // 启动中：按钮内显示 loading，且不可再次点击。
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.6, color: palette.onAcc),
                      ),
                      const SizedBox(width: 6),
                      Text(l10n.svcStart, style: const TextStyle(fontSize: 9.5)),
                    ],
                  )
                : Text(running ? l10n.svcStop : l10n.svcStart, style: const TextStyle(fontSize: 9.5)),
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

String _platformLabel(AppLocalizations l10n, TranslatePlatform p) => switch (p) {
  TranslatePlatform.youdaoZhiYun => l10n.platformYoudao,
};

/// 在线翻译平台凭证（D-047）：平台下拉 + appKey/appSecret，存系统钥匙串。
class _LlmCredentialSection extends ConsumerStatefulWidget {
  const _LlmCredentialSection();

  @override
  ConsumerState<_LlmCredentialSection> createState() => _LlmCredentialSectionState();
}

class _LlmCredentialSectionState extends ConsumerState<_LlmCredentialSection> {
  TranslatePlatform _platform = TranslatePlatform.youdaoZhiYun;
  late final TextEditingController _key;
  late final TextEditingController _secret;
  bool _loaded = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController();
    _secret = TextEditingController();
  }

  @override
  void dispose() {
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _loadOnce(Map<TranslatePlatform, PlatformCredential>? creds) {
    if (_loaded || creds == null) return;
    _loaded = true;
    final c = creds[_platform] ?? const PlatformCredential();
    _key.text = c.appKey;
    _secret.text = c.appSecret;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final creds = ref.watch(credentialProvider).value;
    _loadOnce(creds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingSubTitle(l10n.llmCredTitle),
        SettingRow(
          label: l10n.llmCredTitle,
          why: l10n.llmCredWhy,
          control: AppSelect<TranslatePlatform>(
            value: _platform,
            items: [for (final p in TranslatePlatform.values) (p, _platformLabel(l10n, p))],
            onChanged: (v) {
              setState(() {
                _platform = v;
                _loaded = false;
                _saved = false;
              });
            },
          ),
        ),
        SettingRow(
          label: l10n.llmAppKey,
          control: SizedBox(width: 220, child: _Field(controller: _key)),
        ),
        SettingRow(
          label: l10n.llmAppSecret,
          control: SizedBox(width: 220, child: _Field(controller: _secret, obscure: true)),
        ),
        SettingRow(
          label: l10n.llmCredSave,
          why: _saved ? l10n.llmCredSaved : null,
          control: FilledButton(
            onPressed: () async {
              await ref
                  .read(credentialProvider.notifier)
                  .save(_platform, PlatformCredential(appKey: _key.text, appSecret: _secret.text));
              if (!mounted) return;
              setState(() => _saved = true);
              if (!context.mounted) return;
              showAppToast(context, l10n.llmCredSaved, tone: ToastTone.good);
            },
            style: _primaryStyle(palette),
            child: Text(l10n.llmCredSave, style: const TextStyle(fontSize: 9.5)),
          ),
        ),
      ],
    );
  }
}

/// 远程连接配置（D-045）：地址 + 令牌 + 测试连接。
///
/// 三件事一次问清：能连上 / 令牌对 / 对面引擎起没起。
/// 用 `/api/v1/ping` 而不是 `/health`——后者不校验令牌，证明不了「令牌对」。
class _RemoteSection extends ConsumerStatefulWidget {
  const _RemoteSection();

  @override
  ConsumerState<_RemoteSection> createState() => _RemoteSectionState();
}

class _RemoteSectionState extends ConsumerState<_RemoteSection> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _testing = false;
  RemoteProbe? _result;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(remoteConfigProvider);
    _url = TextEditingController(text: cfg.baseUrl);
    _token = TextEditingController(text: cfg.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final cfg = RemoteConfig(baseUrl: _url.text.trim(), token: _token.text.trim());
    ref.read(remoteConfigProvider.notifier).save(baseUrl: _url.text, token: _token.text);
    setState(() {
      _testing = true;
      _result = null;
    });
    final probe = await ref.read(remotePingProvider)(cfg);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = probe;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingSubTitle(l10n.remoteTitle),
        SettingRow(
          label: l10n.remoteBaseUrl,
          why: l10n.remoteTitleWhy,
          control: SizedBox(
            width: 220,
            child: _Field(controller: _url, hint: l10n.remoteBaseUrlHint),
          ),
        ),
        SettingRow(
          label: l10n.remoteToken,
          control: SizedBox(width: 220, child: _Field(controller: _token, obscure: true)),
        ),
        SettingRow(
          label: l10n.remoteTest,
          why: _result == null
              ? null
              : _result!.ok
              ? (_result!.engineReady ? l10n.remoteOk : l10n.remoteOkNoEngine)
              : '${l10n.remoteFail}：${_result!.message}',
          control: FilledButton(
            onPressed: _testing ? null : _test,
            style: _primaryStyle(palette),
            child: Text(_testing ? l10n.remoteTesting : l10n.remoteTest, style: const TextStyle(fontSize: 9.5)),
          ),
        ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _result!.ok
                  ? (_result!.engineReady ? l10n.remoteOk : l10n.remoteOkNoEngine)
                  : '${l10n.remoteFail}：${_result!.message}',
              style: TextStyle(
                fontSize: 9.5,
                color: _result!.ok ? (_result!.engineReady ? palette.good : palette.warn) : palette.bad,
              ),
            ),
          ),
      ],
    );
  }
}

/// 单行输入框（与 `.select` 同高，避免两种控件在同一列里参差不齐）。
class _Field extends StatelessWidget {
  const _Field({required this.controller, this.hint, this.obscure = false});

  final TextEditingController controller;
  final String? hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(fontSize: 10, color: palette.ink),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 9.5, color: palette.mut),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          filled: true,
          fillColor: palette.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            borderSide: BorderSide(color: palette.line2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            borderSide: BorderSide(color: palette.line2),
          ),
        ),
      ),
    );
  }
}

/// 非桌面端的说明条：讲清「为什么只有远程」。
class _RemoteOnlyNote extends StatelessWidget {
  const _RemoteOnlyNote();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: palette.accSoft, borderRadius: BorderRadius.circular(AppMetrics.radiusCard)),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 12, color: palette.acc),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.settingRemoteOnlyNote, style: TextStyle(fontSize: 9.5, color: palette.ink2)),
          ),
        ],
      ),
    );
  }
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
    // Web / 移动端：没有可选项，不画下拉（画了就是假的可交互控件）。
    if (!supportsLocalEngine) {
      return SettingRow(label: l10n.settingSourceLabel, why: l10n.settingRemoteOnlyNote, def: l10n.sourceRemote);
    }
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
