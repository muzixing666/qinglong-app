part of 'main.dart';

bool? loginSucceeded(dynamic status) => switch (status) {
  0 || '0' || 'success' || true => true,
  1 || '1' || 'fail' || 'failed' || false => false,
  _ => null,
};

DateTime? loginMoment(dynamic value) {
  final number = num.tryParse(str(value));
  if (number != null && number > 0) {
    return DateTime.fromMillisecondsSinceEpoch(
      (number < 100000000000 ? number * 1000 : number).toInt(),
    ).toLocal();
  }
  return DateTime.tryParse(str(value))?.toLocal();
}

String loginTimeLabel(dynamic value) {
  final date = loginMoment(value);
  if (date == null) return '时间未提供';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}

class LoginHistoryPage extends StatefulWidget {
  final HomeState host;
  const LoginHistoryPage({super.key, required this.host});
  @override
  State<LoginHistoryPage> createState() => _LoginHistoryPageState();
}

class _LoginHistoryPageState extends State<LoginHistoryPage> {
  late final scope = widget.host.m.epoch;
  List<Json> records = [];
  bool busy = false;
  String? error;
  int filter = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (scope != widget.host.m.epoch) throw ApiFailure('面板已切换，请重新打开登录记录');
      var data = await widget.host.m.api('GET', '/user/login-log');
      if (data is String) data = jsonDecode(data);
      if (data is! List && !(data is Map && data['data'] is List)) {
        throw ApiFailure('登录记录格式不受支持');
      }
      final list = rows(data)
          .map(
            (row) => row['info'] is Map
                ? Map<String, dynamic>.from(row['info'])
                : row,
          )
          .toList();
      list.sort(
        (a, b) => (loginMoment(b['timestamp'])?.millisecondsSinceEpoch ?? 0)
            .compareTo(
              loginMoment(a['timestamp'])?.millisecondsSinceEpoch ?? 0,
            ),
      );
      if (mounted && scope == widget.host.m.epoch) {
        setState(() => records = list);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = records
        .where(
          (row) =>
              filter == 0 || loginSucceeded(row['status']) == (filter == 1),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录记录'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                for (final item in ['全部', '成功', '失败'].asMap().entries)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(item.value),
                        selected: filter == item.key,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => filter = item.key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: shown.isEmpty ? 1 : shown.length,
                itemBuilder: (c, i) {
                  if (shown.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Center(child: Text(busy ? '正在加载…' : '暂无登录记录')),
                    );
                  }
                  final row = shown[i],
                      success = loginSucceeded(shown[i]['status']);
                  final tone = success == true
                      ? const Color(0xff267d50)
                      : success == false
                      ? const Color(0xffb64e3e)
                      : Theme.of(c).colorScheme.onSurfaceVariant;
                  final platform = str(row['platform']);
                  final device =
                      const {
                        'desktop': '电脑端',
                        'pc': '电脑端',
                        'web': '网页端',
                        'mobile': '移动端',
                        'android': 'Android',
                        'ios': 'iOS',
                      }[platform.toLowerCase()] ??
                      (platform.isEmpty ? '未提供' : platform);
                  final ip = str(
                    row['ip'],
                  ).replaceFirst(RegExp(r'^::ffff:', caseSensitive: false), '');
                  final location = str(row['address']);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  loginTimeLabel(row['timestamp']),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tone.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  success == true
                                      ? '登录成功'
                                      : success == false
                                      ? '登录失败'
                                      : '状态未知',
                                  style: TextStyle(fontSize: 11, color: tone),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            'IP：${ip.isEmpty ? '未提供' : ip}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '登录端：$device',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '位置：$location',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(c).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
