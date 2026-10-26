part of 'main.dart';

extension TaskDeleteFlow on HomeState {
  Future<bool> deleteTasks(List<Json> tasks) async {
    final result = await overlay(
      () => showModalBottomSheet<TaskDeleteResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _TaskDeleteSheet(model: m, tasks: tasks),
      ),
    );
    if (result == null || !mounted) return false;
    if (result.failedScripts.isNotEmpty || result.retainedScripts.isNotEmpty) {
      await overlay(
        () => showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('任务已删除'),
            scrollable: true,
            content: Text(
              [
                if (result.retainedScripts.isNotEmpty)
                  '以下脚本仍被引用或未能确认，已保留：\n${result.retainedScripts.join('\n')}',
                if (result.failedScripts.isNotEmpty)
                  '以下脚本未删除：\n${result.failedScripts.entries.map((e) => '${e.key}：${e.value}').join('\n')}',
              ].join('\n\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      );
    }
    if (result.failedScripts.isEmpty && result.retainedScripts.isEmpty) {
      showAppToast('任务已删除');
    }
    return true;
  }
}

class _TaskDeleteSheet extends StatefulWidget {
  final PanelModel model;
  final List<Json> tasks;
  const _TaskDeleteSheet({required this.model, required this.tasks});
  @override
  State<_TaskDeleteSheet> createState() => _TaskDeleteSheetState();
}

class _TaskDeleteSheetState extends State<_TaskDeleteSheet> {
  TaskScriptPlan? plan;
  String? planError, error;
  bool includeScripts = false, busy = false;
  final selected = <String>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.model.prepareTaskDeletion(widget.tasks);
      if (mounted) setState(() => plan = value);
    } catch (e) {
      if (mounted) setState(() => planError = '$e');
    }
  }

  Future<void> remove() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.model.deleteTasksAndScripts(
        widget.tasks,
        includeScripts ? {...selected} : <String>{},
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible =
        plan?.files.keys
            .where((path) => !plan!.shared.containsKey(path))
            .toList() ??
        <String>[];
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return PopScope(
      canPop: !busy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '删除 ${widget.tasks.length} 个任务？',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text('默认保留脚本文件。删除后无法直接撤销。', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              if (plan == null && planError == null)
                const LinearProgressIndicator(minHeight: 2),
              CheckboxListTile(
                key: const ValueKey('delete-task-scripts'),
                contentPadding: EdgeInsets.zero,
                title: const Text('同时删除对应脚本', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  planError != null
                      ? '脚本识别失败，可仅删除任务'
                      : plan == null
                      ? '正在识别脚本和引用关系…'
                      : '其他任务仍引用的脚本会保留',
                  style: const TextStyle(fontSize: 12),
                ),
                value: includeScripts,
                onChanged: busy || plan == null || eligible.isEmpty
                    ? null
                    : (value) => setState(() {
                        includeScripts = value ?? false;
                        selected
                          ..clear()
                          ..addAll(includeScripts ? eligible : <String>[]);
                      }),
              ),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (plan != null &&
                            (includeScripts || plan!.shared.isNotEmpty))
                          for (final path in plan!.files.keys)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                path,
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: plan!.shared.containsKey(path)
                                  ? Text(
                                      '另有 ${plan!.shared[path]} 个任务使用 · 保留',
                                      style: const TextStyle(fontSize: 11),
                                    )
                                  : null,
                              value: selected.contains(path),
                              onChanged:
                                  busy ||
                                      !includeScripts ||
                                      plan!.shared.containsKey(path)
                                  ? null
                                  : (value) => setState(() {
                                      if (value == true) {
                                        selected.add(path);
                                      } else {
                                        selected.remove(path);
                                      }
                                    }),
                            ),
                        if (plan != null && plan!.unresolvedTasks > 0)
                          Text(
                            '${plan!.unresolvedTasks} 个任务未能唯一识别脚本，将仅删除任务。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: duration,
                child: error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(error),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: busy ? null : remove,
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline, size: 18),
                      label: Text(
                        busy
                            ? '正在删除…'
                            : includeScripts && selected.isNotEmpty
                            ? '删除任务及 ${selected.length} 个脚本'
                            : '仅删除任务',
                        style: const TextStyle(fontSize: 12),
                      ),
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
