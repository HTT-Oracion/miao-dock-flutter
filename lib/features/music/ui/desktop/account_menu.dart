import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/platform_logo.dart';
import '../widgets/song_row.dart';

/// 账号菜单（N05）：头像 / 昵称 / 当前音源 / 四平台状态 / 退出登录。
///
/// 位置：由顶栏账号 chip 在点击时写入的**全局矩形**决定 —— 菜单右对齐、贴在
/// 胶囊正下方 6px（设计稿 `.acct` + `.pop` 的位置关系）。
///
/// 为什么走 [OverlayEntry] 而不是在本层 `Positioned`：
/// 菜单挂在壳层的 Stack 里，而栈的坐标原点是「工具条之下」，用全局坐标会整体
/// 下移一个工具条高度（实测菜单出现在内容区中间）。Overlay 的坐标系就是整个
/// 窗口，global → position 一一对应，不需要手工换算。
/// 账号菜单的落位（纯函数，便于单测）：
/// 右对齐锚点、垂直贴在其下方 6px，并按窗口边界夹紧。
Rect accountMenuRect({required Rect? anchor, required Size screen, double width = 230}) {
  const margin = 8.0;
  final left = anchor == null
      ? screen.width - width - 16
      : (anchor.right - width).clamp(margin, screen.width - width - margin);
  final top = anchor == null ? 56.0 : (anchor.bottom + 6).clamp(margin, screen.height - 240);
  return Rect.fromLTWH(left.toDouble(), top.toDouble(), width, 0);
}

class AccountMenuPopover extends ConsumerStatefulWidget {
  const AccountMenuPopover({super.key, this.width = 230});

  /// 菜单宽度（设计稿 `.pop` 230）。
  final double width;

  @override
  ConsumerState<AccountMenuPopover> createState() => _AccountMenuPopoverState();
}

class _AccountMenuPopoverState extends ConsumerState<AccountMenuPopover> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show();
    });
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _close() => ref.read(musicUiProvider.notifier).setAccountMenu(false);

  void _show() {
    final overlay = Overlay.of(context);
    final rect = accountMenuRect(
      anchor: ref.read(musicAccountAnchorProvider),
      screen: MediaQuery.sizeOf(context),
      width: widget.width,
    );
    final left = rect.left;
    final top = rect.top;

    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // 透明遮罩：点空白关闭（N05）；不吃滚动 / hover。
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close, child: const SizedBox.expand()),
          ),
          Positioned(
            key: const ValueKey('music-account-menu'),
            left: left,
            top: top,
            width: widget.width,
            child: _MenuBody(onClose: _close),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 菜单内容（与锚点定位解耦，方便测试单独挂载）。
class _MenuBody extends ConsumerWidget {
  const _MenuBody({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(musicAccountProvider);

    String badgeOf(MusicPlatform p) {
      if (p == account.cur) return l10n.musicBadgeCur;
      return account.isLogged(p) ? l10n.musicBadgeLogged : l10n.musicBadgeOff;
    }

    return Material(
      color: Colors.transparent,
      child: MusicPanelBox(
        width: 230,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: account.logged ? palette.acc : palette.hi,
                    child: Text(
                      account.logged && (account.nick?.isNotEmpty ?? false) ? account.nick!.substring(0, 1) : '?',
                      style: TextStyle(
                        fontSize: AppFont.px13,
                        fontWeight: FontWeight.w700,
                        color: account.logged ? palette.onAcc : palette.mut,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.logged ? (account.nick ?? '') : l10n.musicNotLogged,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
                        ),
                        Text(
                          l10n.musicCurSourceAria(platformBrands[account.cur]?.label ?? ''),
                          style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const MusicMenuDivider(),
            for (final p in MusicPlatform.values.where((p) => p != MusicPlatform.local))
              MusicMenuTile(
                leading: PlatformLogo(platform: p, size: 14),
                label: platformBrands[p]?.label ?? '',
                sub: badgeOf(p),
                checked: p == account.cur,
                onTap: () => _onPlatformTap(context, ref, p),
              ),
            if (account.logged) ...[
              const MusicMenuDivider(),
              MusicMenuTile(
                icon: LucideIcons.logOut,
                label: l10n.musicLogout,
                danger: true,
                onTap: () {
                  ref.read(musicAccountProvider.notifier).logout();
                  onClose();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onPlatformTap(BuildContext context, WidgetRef ref, MusicPlatform p) {
    final account = ref.read(musicAccountProvider);
    final l10n = AppLocalizations.of(context);
    // 未登录优先：当前源（如网易云）未登录时点它，也要拉起登录弹窗（用户口径）。
    if (!account.isLogged(p)) {
      onClose();
      ref.read(musicUiProvider.notifier).openLogin(p);
      return;
    }
    if (p == account.cur) {
      onClose();
      return;
    }
    ref.read(musicAccountProvider.notifier).switchPlatform(p);
    onClose();
    showAppToast(context, l10n.musicSwitchSourceToast(platformBrands[p]?.label ?? ''), tone: ToastTone.good);
  }
}
