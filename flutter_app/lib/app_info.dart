part of 'main.dart';

const projectUrl = 'https://github.com/muzixing666/qinglong-app';
const downloadUrl = '$projectUrl/releases/latest';

class AppInfoPage extends StatefulWidget {
  final bool agreement;
  const AppInfoPage({super.key, this.agreement = false});
  @override
  State<AppInfoPage> createState() => _AppInfoPageState();
}

class _AppInfoPageState extends State<AppInfoPage> {
  late final content = rootBundle.loadString('assets/USER_AGREEMENT.txt');
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.agreement ? '用户协议' : '下载与更新')),
    body: widget.agreement
        ? FutureBuilder<String>(
            future: content,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('协议加载失败，请重新打开'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: SelectableText(
                  snapshot.data!,
                  style: const TextStyle(fontSize: 14, height: 1.7),
                ),
              );
            },
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '青龙掌控',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '从 GitHub Releases 获取正式安装包和版本说明。更新时请覆盖安装，以保留已有连接。',
                    ),
                    const SizedBox(height: 14),
                    const SelectableText(
                      downloadUrl,
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('前往下载'),
                          onPressed: () => guard(
                            context,
                            () => Native.channel.invokeMethod<void>(
                              'openExternal',
                              downloadUrl,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('复制地址'),
                          onPressed: () => Clipboard.setData(
                            const ClipboardData(text: downloadUrl),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}
