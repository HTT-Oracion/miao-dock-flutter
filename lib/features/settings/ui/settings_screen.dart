import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/process/service_controller.dart';
import '../../../core/storage/paths.dart';
import '../../../core/storage/shell_prefs.dart';
import '../../../app/shell/shell_controller.dart';
import '../../../app/pairing_token_controller.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/responsive.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/app_select.dart';
import '../../../shared/widgets/buttons.dart';
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

    // 深链：`/settings?section=translate`（引导页「去设置远程配置」）。
    // 🔴 本屏是 ConsumerWidget（无 State），只能在 build 里处理；
    // 且必须检查当前值是否已命中，否则每次 build 都会把用户手动切的
    // 分组拽回 query 指定的那个（用户点不动其它分组）。
    final wanted = GoRouter.maybeOf(context)?.state.uri.queryParameters['section'];
    if (wanted != null && wanted.isNotEmpty) {
      final current = ref.read(_sectionProvider);
      if (current != wanted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) ref.read(_sectionProvider.notifier).jump(wanted);
        });
      }
    }

    final selected = ref.watch(_sectionProvider);

    // 窄屏：左栏 208 会把内容区压到不足 200 —— 改成顶部横向滚动标签。
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (id, labelKey, _) in _sections)
                  _MobileTab(
                    label: _labelOf(l10n, labelKey),
                    // 窄屏**不显示计数**：数字是宽屏侧栏的分区规模提示，
                    // 贴到顶部标签上会被读成"13 条未读/13 项"（用户实测困惑，D-139）。
                    active: selected == id,
                    onTap: () => ref.read(_sectionProvider.notifier).select(id),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: palette.line),
          Expanded(child: _sectionBody(selected, l10n)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 208,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部「设置」标题已移除（用户要求）：左栏只剩导航项本身。
              const SizedBox(height: 8),
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
        Expanded(child: _sectionBody(selected, l10n)),
      ],
    );
  }

  /// 分区正文 —— 宽屏（左栏）与窄屏（顶部标签）**共用**，保证两套布局内容一致。
  Widget _sectionBody(String selected, AppLocalizations l10n) => switch (selected) {
    'general' => const _GeneralSection(),
    'translate' => const _TranslateSection(),
    _ => _PlaceholderSection(label: _labelOf(l10n, selected == 'media' ? 'settingsNavMedia' : 'settingsNavAbout')),
  };

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

  /// 外部跳转（如引导页「去设置远程配置」）指定分组。
  void jump(String id) {
    if (state != id) state = id;
  }
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
          // 🔴 必须显式传：InkWell 内部 MouseRegion（桌面默认 basic）比外层
          // MouseRegion 更内侧、优先生效，不传则手型永远出不来（D-119）。
          mouseCursor: SystemMouseCursors.click,
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
                    fontSize: AppFont.px10_5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? palette.ink : palette.ink2,
                  ),
                ),
                const Spacer(),
                if (count != null)
                  Text(
                    '$count',
                    style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
                  ),
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
          style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
        ),
        const SizedBox(height: 3),
        Text(
          blurb,
          style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
        ),
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
    final collapsed = ref.watch(navCollapsedProvider);

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
            control: AppButton(
              label: l10n.settingSpecCheckRun,
              variant: AppButtonVariant.primary,
              onTap: null,
              clickable: false,
            ),
          ),
          // 侧栏展开开关：与侧栏自身的收起/展开按钮**同一个状态**（navCollapsedProvider）。
          // 移动端没有可折叠侧栏（用底部导航），因此不显示该设置。
          if (MediaQuery.sizeOf(context).width > AppMetrics.breakpoint)
            SettingRow(
              label: l10n.settingSidebarLabels,
              why: l10n.settingSidebarLabelsWhy,
              def: collapsed ? l10n.settingSidebarCollapsed : l10n.settingSidebarExpanded,
              control: AppSwitch(
                // 开关「开」= 展开（不折叠），与用户直觉一致。
                value: !collapsed,
                onChanged: (v) => ref.read(navCollapsedProvider.notifier).set(!v),
              ),
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
      // 真正导出 .txt：弹保存对话框，用户能选位置、能取消。
      // 之前没传这个回调 ⇒ 点下载只复制到剪贴板，看起来"没生效"。
      onExport: (text, suggestedName) => _saveLog(context, text, suggestedName),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // 壳层已全局订阅；这里保留订阅，让设置页被单独挂载时也能同步真实状态。
    ref.watch(engineStatusPollProvider);
    final view = ref.watch(notReadyViewProvider);
    final install = ref.watch(engineInstallProvider);
    // 🔴 必须直接看 engineStateProvider：`notReadyViewProvider` 传的是 `status: null`，
    // 其 `engine` 恒为 off —— 用它判断会导致按钮永远没有 loading 态。
    final engineState = ref.watch(engineStateProvider);
    final llmState = ref.watch(llmStateProvider);
    final running = engineState.isReady;
    // 引擎在跑但 LLM 缺 ⇒ 服务在、翻译不可用：圆点黄色 + 文字说明（不再是纯绿/纯灰两态）。
    final llmMissing = running && !llmState.isReady;

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
      _ => llmMissing ? l10n.svcLlmMissing : (running ? l10n.svcEngineReady : l10n.svcEngineOff),
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
                      style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w600, color: palette.ink),
                    ),
                    const SizedBox(width: 6),
                    // 状态圆点：绿=就绪（两进程都在跑）、黄=部分就绪、灰=停止。
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: running
                            ? (llmMissing ? palette.warn : palette.good)
                            : (engineState == EngineRuntimeState.failed ? palette.bad : palette.divider),
                        shape: BoxShape.circle,
                      ),
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
                    fontSize: AppFont.px10,
                    color: startError != null ? palette.bad : (blockedReason == null ? palette.ink2 : palette.warn),
                  ),
                ),
              ],
            ),
          ),
          AppButton(
            // 运行中可停止；未启动时必须满足前置条件且不在启动中。
            label: starting ? l10n.svcStart : (running ? l10n.svcStop : l10n.svcStart),
            loading: starting,
            variant: AppButtonVariant.primary,
            fontSize: AppFont.px9_5,
            onTap: running
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
          control: SizedBox(
            width: 220,
            child: AppInput(controller: _key, hint: l10n.llmAppKeyHint),
          ),
        ),
        SettingRow(
          label: l10n.llmAppSecret,
          control: SizedBox(
            width: 220,
            child: AppInput(controller: _secret, hint: l10n.llmAppSecretHint, obscure: true),
          ),
        ),
        SettingRow(
          label: l10n.llmCredSave,
          why: _saved ? l10n.llmCredSaved : null,
          control: AppButton(
            label: l10n.llmCredSave,
            variant: AppButtonVariant.primary,
            fontSize: AppFont.px9_5,
            onTap: () async {
              await ref
                  .read(credentialProvider.notifier)
                  .save(_platform, PlatformCredential(appKey: _key.text, appSecret: _secret.text));
              if (!mounted) return;
              setState(() => _saved = true);
              if (!context.mounted) return;
              showAppToast(context, l10n.llmCredSaved, tone: ToastTone.good);
            },
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
  bool _touched = false;

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

  /// 令牌与远程地址均必填，地址必须是合法 http(s) URL。
  String? _tokenError(AppLocalizations l10n) {
    if (!_touched) return null;
    return _token.text.trim().isEmpty ? l10n.remoteTokenRequired : null;
  }

  String? _urlError(AppLocalizations l10n) {
    final raw = _url.text.trim();
    if (raw.isEmpty) return _touched ? l10n.remoteUrlRequired : null;
    final uri = Uri.tryParse(raw);
    final ok = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    return ok ? null : l10n.remoteUrlInvalid;
  }

  bool _canTest(AppLocalizations l10n) =>
      _token.text.trim().isNotEmpty && _url.text.trim().isNotEmpty && _urlError(l10n) == null;

  Future<void> _test() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _touched = true);
    if (!_canTest(l10n)) return;
    final persisted = ref.read(remoteConfigProvider.notifier).save(baseUrl: _url.text, token: _token.text);
    debugPrint('[remote] save persisted=$persisted');
    setState(() => _testing = true);
    final probe = await ref.read(remoteVerificationProvider.notifier).verify();
    debugPrint(
      '[remote] probe=${probe == null ? "null" : "ok=${probe.ok} engineReady=${probe.engineReady} ${probe.message}"}',
    );
    if (!mounted) return;
    setState(() => _testing = false);
    final probeOk = probe?.ok == true;
    final engineReady = probe?.engineReady == true;
    String message;
    if (probeOk && persisted) {
      message = engineReady ? l10n.remoteTestOkToast : '${l10n.remoteTestOkToast}（${l10n.remoteOkNoEngine}）';
    } else if (probeOk) {
      message = l10n.remoteConfigPersistFailed;
    } else if (probe == null) {
      message = l10n.remoteTestFailToast;
    } else {
      message = '${l10n.remoteTestFailToast}：${probe.message}';
    }
    // 成功/失败都吐司（用户要求）。
    final success = probeOk && persisted;
    showAppToast(context, message, tone: success ? (engineReady ? ToastTone.good : ToastTone.warn) : ToastTone.bad);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // **一行**：令牌 + 远程地址 + 测试按钮（用户要求）。
    // 令牌定宽（64 hex 遮蔽显示，200 足够容纳提示与可见段）；地址用 Expanded
    // 吃掉剩余宽度（URL 长度不定，宽输入更合理），按钮因此自然**贴行最右**。
    // 按钮规格对齐设置页 `_primaryStyle`（内距 18 / 字 11 / w600），
    // 高度取 36 与同行输入框同高（D-055：同排控件同高更稳）。
    final tokenField = AppInput(
      controller: _token,
      hint: l10n.remoteTokenHint,
      obscure: true,
      errorText: _tokenError(l10n),
      onChanged: (v) {
        // 输入即进内存态：服务定位器（投放链路）立刻能用，落盘等「测试连接」。
        ref.read(remoteConfigProvider.notifier).stage(token: v);
        ref.read(remoteVerificationProvider.notifier).invalidate();
        setState(() {});
      },
    );
    final urlField = AppInput(
      controller: _url,
      hint: l10n.remoteBaseUrlHint2,
      errorText: _urlError(l10n),
      onChanged: (v) {
        ref.read(remoteConfigProvider.notifier).stage(baseUrl: v);
        ref.read(remoteVerificationProvider.notifier).invalidate();
        setState(() {});
      },
    );
    final testButton = AppButton(
      label: _testing ? l10n.remoteTesting : l10n.remoteTest,
      onTap: _testing ? null : _test,
      clickable: !_testing,
      variant: AppButtonVariant.primary,
      height: 26,
      horizontalPadding: 18,
      fontSize: AppFont.px9_5,
      fontWeight: FontWeight.w600,
    );

    // 窄屏：三个控件**各占一行**。并排时 200 + 输入框 + 按钮在 390 宽下
    // 会把输入框挤成一条缝（用户实测"太挤"，D-139）。
    if (context.isMobile) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tokenField,
            const SizedBox(height: 8),
            urlField,
            const SizedBox(height: 10),
            // 用 AppButton.width 撑满：`FittedBox` 会把文字一起缩放（实测被拉变形）。
            AppButton(
              label: _testing ? l10n.remoteTesting : l10n.remoteTest,
              onTap: _testing ? null : _test,
              clickable: !_testing,
              loading: _testing,
              variant: AppButtonVariant.primary,
              width: double.infinity,
              height: 40,
              fontSize: AppFont.px11_5,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 200, child: tokenField),
          const SizedBox(width: 8),
          Expanded(child: urlField),
          const SizedBox(width: 8),
          // 高度 = 同行输入框（D-055：同排控件同高）。
          testButton,
        ],
      ),
    );
  }
}

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
            child: Text(
              l10n.settingRemoteOnlyNote,
              style: TextStyle(fontSize: AppFont.px9_5, color: palette.ink2),
            ),
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
      child: Text(
        text,
        style: TextStyle(fontSize: AppFont.px8_5, color: palette.good),
      ),
    );
  }
}

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
          // 【大模型翻译】暂时隐藏（llmSourceEnabled）；实现保留，打开常量即恢复。
          if (llmSourceEnabled) (TranslateSource.llm, l10n.sourceLlm),
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
    final autoEngine = ref.watch(_autoStartEngineProvider);

    return Column(
      children: [
        SettingRow(
          label: l10n.svcAutoStartEngine,
          why: l10n.svcAutoStartEngineWhy,
          control: AppSwitch(value: autoEngine, onChanged: (v) => ref.read(_autoStartEngineProvider.notifier).set(v)),
        ),
        const _PairingTokenRow(),
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
              style: TextStyle(fontSize: AppFont.px9, color: palette.ink2, fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}

/// 配对令牌行：本机 mangasvc 的 `X-Box-Token`，其他端远程连接时随请求携带。
///
/// 令牌来自服务启动时的 `--print-token`（D-065），只有本应用拉起服务才拿得到；
/// 用户手动启动服务时如实说明，不放空行假装正常。
class _PairingTokenRow extends ConsumerWidget {
  const _PairingTokenRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final tokenState = ref.watch(pairingTokenProvider);
    final token = tokenState.value ?? ref.watch(serviceSupervisorProvider)?.token;

    return SettingRow(
      label: l10n.pairingTokenLabel,
      why: l10n.pairingTokenWhy,
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              token ?? l10n.pairingTokenUnavailable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFont.px9,
                color: token == null ? palette.mut : palette.ink2,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (token != null) ...[
            const SizedBox(width: 10),
            AppButton(
              label: l10n.pairingTokenCopy,
              variant: AppButtonVariant.secondary,
              height: 24,
              horizontalPadding: 10,
              fontSize: AppFont.px9_5,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (!context.mounted) return;
                showAppToast(context, l10n.pairingTokenCopied, tone: ToastTone.good);
              },
            ),
            const SizedBox(width: 6),
            AppButton(
              label: l10n.pairingTokenRefresh,
              variant: AppButtonVariant.secondary,
              height: 24,
              horizontalPadding: 10,
              fontSize: AppFont.px9_5,
              loading: tokenState.isLoading,
              onTap: tokenState.isLoading
                  ? null
                  : () async {
                      final refreshed = await ref.read(pairingTokenProvider.notifier).refreshToken();
                      if (!context.mounted) return;
                      if (refreshed != null) {
                        showAppToast(context, l10n.pairingTokenRefreshed, tone: ToastTone.good);
                      } else {
                        // 带上原因：404（服务是旧版没这条路由）和 403 排障方向完全不同。
                        final state = ref.read(pairingTokenProvider);
                        final err = state.hasError ? state.error : null;
                        showAppToast(
                          context,
                          err == null ? l10n.pairingTokenRefreshFailed : '${l10n.pairingTokenRefreshFailed}：$err',
                          tone: ToastTone.bad,
                        );
                      }
                    },
            ),
          ],
        ],
      ),
    );
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
      child: Text(
        label,
        style: TextStyle(fontSize: AppFont.px13, color: palette.mut),
      ),
    );
  }
}

/// 保存翻译日志为 .txt（桌面走系统保存对话框）。
/// 返回 false = 用户取消，调用方不弹「已导出」。
Future<bool> _saveLog(BuildContext context, String text, String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Text', extensions: ['txt']),
    ],
  );
  if (location == null) return false;
  await File(location.path).writeAsString(text);
  return true;
}

/// 窄屏顶部标签（设置分区切换）。
///
/// 只做「横排标签」这一种排布，外观复用 [AppButton] —— 不引入第二套按钮样式。
class _MobileTab extends StatelessWidget {
  const _MobileTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: AppButton(
        label: label,
        onTap: onTap,
        variant: active ? AppButtonVariant.secondary : AppButtonVariant.ghost,
        height: 30,
        horizontalPadding: 12,
        fontSize: AppFont.px10_5,
        color: active ? palette.textPrimary : palette.textSecondary,
      ),
    );
  }
}
