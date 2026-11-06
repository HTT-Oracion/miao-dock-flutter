import 'package:desktop_drop/desktop_drop.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_input.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../controller/drop_controller.dart';

/// 投放页**桌面**表单。
///
/// 与移动端分开维护（D-138）：拖拽区、并排按钮、更大的卡片内距都是桌面专属。
/// 壳（`drop_screen.dart`）只负责取图 / 提交，两端共用。
///
/// 重设计稿新增：提交成功回执卡（留在本页，不再直接跳队列）、
/// 「最近投放」（读真实任务列表）、三步说明、拖拽区图标球呼吸动画。
class DropDesktopBody extends StatelessWidget {
  const DropDesktopBody({
    super.key,
    required this.state,
    required this.over,
    required this.submitting,
    required this.onPickImages,
    required this.onPickFolder,
    required this.onDragEnter,
    required this.onDragExit,
    required this.onDrop,
    required this.onNameChanged,
    required this.onClear,
    required this.onRemoveFile,
    required this.onSubmit,
  });

  final DropState state;
  final bool over;

  /// 提交请求在途：按钮禁用 + 文案换「提交中…」（防双击重复排队）。
  final bool submitting;
  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;
  final VoidCallback onDragEnter;
  final VoidCallback onDragExit;
  final ValueChanged<List<String>> onDrop;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onClear;
  final ValueChanged<int> onRemoveFile;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final receipt = state.receipt;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 双栏（重设计稿 drop-grid：左 1.1 / 右 0.9，gap 14）。
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左：拖拽区 + 待投放清单。
                  Expanded(
                    flex: 11,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DropZone(
                          over: over,
                          onPickImages: onPickImages,
                          onPickFolder: onPickFolder,
                          onDragEnter: onDragEnter,
                          onDragExit: onDragExit,
                          onDrop: onDrop,
                        ),
                        const SizedBox(height: 12),
                        _PendingCard(state: state, onRemoveFile: onRemoveFile),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 右：漫画信息 + 本次规则 + 提交按钮 + 回执。
                  Expanded(
                    flex: 9,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoCard(state: state, onNameChanged: onNameChanged),
                        const SizedBox(height: 12),
                        _RulesCard(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                label: submitting
                                    ? l10n.dropSubmitBusy
                                    : state.files.isEmpty
                                    ? l10n.dropSubmit
                                    : '${l10n.dropSubmit} ${state.files.length}',
                                onTap: onSubmit,
                                clickable: onSubmit != null && !submitting,
                                variant: AppButtonVariant.primary,
                                height: 36,
                                fontSize: AppFont.px12_5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AppButton(
                              label: l10n.dropClear,
                              onTap: state.files.isEmpty ? null : onClear,
                              clickable: state.files.isNotEmpty,
                              variant: AppButtonVariant.ghost,
                              border: true,
                              height: 36,
                              horizontalPadding: 20,
                              fontSize: AppFont.px12_5,
                            ),
                          ],
                        ),
                        if (receipt != null) ...[
                          const SizedBox(height: 12),
                          _ReceiptCard(count: receipt.count, position: receipt.position),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 设计稿 dcard 基座（panel 底 / line2 边框 / r12 / p 14×16）────────────────

class _DCard extends StatelessWidget {
  const _DCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// dcard 标题（h4：12/700）+ 副说明（hint：10px mut）。
class _DCardHead extends StatelessWidget {
  const _DCardHead({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w700, color: palette.ink),
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: TextStyle(fontSize: AppFont.px10, height: 1.6, color: palette.mut),
          ),
        ],
      ],
    );
  }
}

/// meta-row（设计稿：10.5px、虚线底、label mut / value ink）。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
          ),
          Text(
            value,
            style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: palette.ink),
          ),
        ],
      ),
    );
  }
}

/// 待投放清单卡（左栏下）：标题带张数/批数 + hint + 文件网格。
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.state, required this.onRemoveFile});

  final DropState state;
  final ValueChanged<int> onRemoveFile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return _DCard(
      children: [
        _DCardHead(title: '', hint: l10n.dropPendingHint),
        const SizedBox(height: 6),
        Text(
          l10n.dropPendingTitle(
            state.files.length,
            state.batchCount > 1 ? l10n.dropPendingBatchSuffix(state.batchCount) : '',
          ),
          style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w700, color: palette.ink),
        ),
        const SizedBox(height: 8),
        if (state.files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              l10n.dropPendingEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
            ),
          )
        else
          _FileList(state: state, maxHeight: 170, onRemoveFile: onRemoveFile),
      ],
    );
  }
}

/// 漫画信息卡（右栏上）：名称三态提示 + 元信息四行（落盘/预计输出无回执显「—」）。
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.state, required this.onNameChanged});

  final DropState state;
  final ValueChanged<String> onNameChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return _DCard(
      children: [
        _DCardHead(title: l10n.dropInfoCardTitle, hint: l10n.dropInfoCardHint),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: l10n.dropFieldName),
              TextSpan(
                text: '*',
                style: TextStyle(color: AppPalette.of(context).bad),
              ),
            ],
          ),
          style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: AppPalette.of(context).ink),
        ),
        const SizedBox(height: 4),
        _NameInput(value: state.name, onChanged: onNameChanged),
        const SizedBox(height: 4),
        Text(
          l10n.dropComicNameHint,
          style: TextStyle(fontSize: AppFont.px9_5, height: 1.6, color: palette.mut),
        ),
        const SizedBox(height: 10),
        _MetaRow(label: l10n.dropMetaSource, value: l10n.dropMetaSourceValue),
        _MetaRow(
          label: l10n.dropMetaBatch,
          value: state.files.isEmpty
              ? l10n.dropMetaBatchEmpty
              : l10n.dropMetaBatchValue(state.files.length, state.batchCount),
        ),
        _MetaRow(label: l10n.dropMetaRootDir, value: l10n.dropMetaRootDirValue),
      ],
    );
  }
}

/// 本次规则卡（右栏中）：读真实设置，不在投放页改。
class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return _DCard(
      children: [
        Text(
          l10n.dropRulesTitle,
          style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w700, color: palette.ink),
        ),
        const SizedBox(height: 4),
        _MetaRow(label: l10n.dropRulesDirection, value: l10n.dropRulesDirectionValue),
        _MetaRow(label: l10n.dropRulesTier, value: l10n.dropRulesTierValue),
        _MetaRow(label: l10n.dropRulesSource, value: l10n.dropRulesSourceValue),
        _MetaRow(label: l10n.dropRulesBatch, value: l10n.dropRulesBatchValue),
        const SizedBox(height: 8),
        Text(
          l10n.dropRulesNote,
          style: TextStyle(fontSize: AppFont.px10, height: 1.6, color: palette.ink2),
        ),
      ],
    );
  }
}

/// 拖拽区（`.dropzone`：圆角 6 / 1px 描边；hover 与拖入都是主色）。
///
/// **桌面专属**：移动端没有 HTML5 拖拽，用点击选图代替。
class _DropZone extends StatefulWidget {
  const _DropZone({
    required this.over,
    required this.onPickImages,
    required this.onPickFolder,
    required this.onDragEnter,
    required this.onDragExit,
    required this.onDrop,
  });

  final bool over;
  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;
  final VoidCallback onDragEnter;
  final VoidCallback onDragExit;
  final ValueChanged<List<String>> onDrop;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> with SingleTickerProviderStateMixin {
  bool _hover = false;
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    // 图标球呼吸（重设计稿 3.2s 往返）：AnimationController 而非 flutter_animate 的
    // repeat() —— 后者在 widget 测试环境会留下 pending Timer，挂掉整批测试。
    _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final active = widget.over || _hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: DropTarget(
        onDragEntered: (_) => widget.onDragEnter(),
        onDragExited: (_) => widget.onDragExit(),
        onDragDone: (details) => widget.onDrop(details.files.map((f) => f.path).toList()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          decoration: BoxDecoration(
            color: active ? palette.accSoft : Colors.transparent,
            border: Border.all(color: active ? palette.acc : palette.line2, width: 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _breath,
                builder: (context, child) {
                  // 呼吸位移 0→-6；悬停/拖入时呼吸停在抬到位的位置（-4）。
                  final dy = active ? -4.0 : -6 * _breath.value;
                  return Transform.translate(offset: Offset(0, dy), child: child);
                },
                child: Icon(
                  LucideIcons.upload,
                  size: 40,
                  color: active ? palette.acc : palette.acc.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                active ? l10n.dropDropHintActive : l10n.dropDropHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFont.px15,
                  fontWeight: FontWeight.w600,
                  color: active ? palette.acc : palette.ink,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  l10n.dropSpec,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppButton(
                    label: l10n.dropPickImages,
                    onTap: widget.onPickImages,
                    variant: AppButtonVariant.primary,
                    height: 28,
                    horizontalPadding: 14,
                    fontSize: AppFont.px12,
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: l10n.dropPickFolder,
                    onTap: widget.onPickFolder,
                    variant: AppButtonVariant.ghost,
                    border: true,
                    height: 28,
                    horizontalPadding: 14,
                    fontSize: AppFont.px12,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 投放页次级按钮：统一走 [AppButton]。
/// `.field label`：14/500，必填项带红 `*`。

/// `.finput`：44 高 / 圆角 6 / 聚焦换主色。
class _NameInput extends StatefulWidget {
  const _NameInput({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NameInput> createState() => _NameInputState();
}

class _NameInputState extends State<_NameInput> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppInput(
      controller: _c,
      hint: AppLocalizations.of(context).dropComicNamePlaceholder,
      height: 44,
      fontSize: AppFont.px14,
      onChanged: widget.onChanged,
    );
  }
}

/// `.flist`：描边容器 + 每行 26 高 + 右侧批次标签。
class _FileList extends StatelessWidget {
  const _FileList({required this.state, required this.maxHeight, required this.onRemoveFile});

  final DropState state;
  final double maxHeight;
  final ValueChanged<int> onRemoveFile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 3.2,
        ),
        itemCount: state.files.length,
        shrinkWrap: true,
        itemBuilder: (context, i) {
          final fileName = state.files[i].split(RegExp(r'[/\\]')).last;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.image, size: 14, color: palette.mut),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: palette.accSoft, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    l10n.dropBatchLabel(state.batchOf(i)),
                    style: TextStyle(fontSize: AppFont.px8_5, color: palette.accent),
                  ),
                ),
                const SizedBox(width: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => onRemoveFile(i),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
                      child: Icon(LucideIcons.x, size: 10, color: palette.mut),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 落盘路径预览（服务端才做名称规范化，这里不猜具体路径）。

/// 提交回执卡（重设计稿 `.receipt`）。
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.count, required this.position});

  final int count;
  final int position;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.good.withValues(alpha: 0.08),
        border: Border.all(color: palette.good.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dropReceiptTitle,
            style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w700, color: palette.good),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.dropReceiptPos(count, position),
            style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              AppButton(
                label: l10n.dropReceiptLibrary,
                onTap: () => context.go('/manga/library'),
                variant: AppButtonVariant.primary,
                height: 28,
                horizontalPadding: 12,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.dropReceiptQueue,
                onTap: () => context.go('/manga/queue'),
                variant: AppButtonVariant.ghost,
                border: true,
                height: 28,
                horizontalPadding: 12,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
