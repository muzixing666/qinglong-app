part of 'main.dart';

extension _DesktopNavigation on HomeState {
  Future<void> consumeShortcut() async {
    try {
      final page = await Native.channel.invokeMethod<String>('consumeShortcut');
      if (!mounted || !pages.contains(page)) return;
      if (!m.initialized) {
        pendingShortcut = page;
        return;
      }
      await navigateShortcut(page!);
    } catch (_) {}
  }

  Future<void> navigateShortcut(String page) async {
    if (!mounted || !pages.contains(page) || shortcutBusy) return;
    shortcutBusy = true;
    try {
      for (final guard in leaveGuards.values.toList().reversed) {
        if (!await guard()) return;
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      m.navigate(page);
    } finally {
      shortcutBusy = false;
    }
  }

  void syncHomeWidget() {
    if (!m.initialized || (m.demo && m.servers.isNotEmpty)) return;
    final tasks = m.demo ? null : m.cache['tasks'];
    final total = tasks?.length ?? -1,
        active = tasks?.where((row) => row['status'] == 0).length ?? -1;
    final server = m.servers
        .where((row) => str(row['id']) == m.activeId)
        .firstOrNull;
    final name = str(server?['name']).isEmpty ? '青龙面板' : str(server?['name']);
    final fingerprint =
        '${m.activeId}|$name|$total|$active|${m.taskSyncedAt ~/ 60000}|${m.dark}';
    if (fingerprint == lastWidgetFingerprint) return;
    lastWidgetFingerprint = fingerprint;
    unawaited(
      Native.channel
          .invokeMethod<void>('widgetState', {
            'serverId': m.activeId,
            'panel': name,
            'total': total,
            'running': active,
            'updated': m.taskSyncedAt,
          })
          .catchError((_) {}),
    );
  }
}

class DesktopPage extends StatelessWidget {
  const DesktopPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('桌面快捷与小组件')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '桌面小组件',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text('查看任务总数、运行中数量和更新时间，支持刷新及任务、变量、脚本快捷入口。'),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.add_to_home_screen, size: 18),
                label: const Text('添加到桌面'),
                onPressed: () => guard(context, () async {
                  final supported =
                      await Native.channel.invokeMethod<bool>('pinWidget') ??
                      false;
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          supported ? '请在系统弹窗中确认添加' : '请长按桌面空白处，选择小组件，再找到青龙掌控',
                        ),
                      ),
                    );
                  }
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '图标长按快捷入口',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text('长按桌面图标，直达任务、变量、脚本和面板管理。'),
            ],
          ),
        ),
      ],
    ),
  );
}
