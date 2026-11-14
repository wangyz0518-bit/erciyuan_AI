import 'package:material_ui/material_ui.dart';

import 'avatar_live2d_demo.dart';
import 'avatar_video_demo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: '人物方案对比',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff7762a4)),
      ),
      home: const AvatarDemoMenu(),
    ),
  );
}

class AvatarDemoMenu extends StatelessWidget {
  const AvatarDemoMenu({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('人物方案 · 双 Demo')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('预设完整动作，自然待机', style: TextStyle(fontSize: 24)),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            title: const Text('A · Live2D 实时模型'),
            subtitle: const Text('官方 Haru / Mark 样例，查看模型实际动作。当前角色尚未完成绑定。'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AvatarLive2dDemo()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('B · 视频动作播放器'),
            subtitle: const Text('导入待机、挥手、换重心视频。当前未内置 AI 动作素材。'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AvatarVideoDemo()),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('这是技术演示入口。两个方案的同角色效果、外部标准包及双端真机验收仍待完成。'),
      ],
    ),
  );
}
