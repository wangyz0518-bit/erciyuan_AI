import 'package:flutter/widgets.dart';

import 'live2d_controller.dart';

class Live2dView extends StatelessWidget {
  const Live2dView({super.key, required this.controller});
  final Live2dController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => controller.textureId == null
        ? const SizedBox.expand()
        : FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 720,
              height: 1280,
              child: Texture(textureId: controller.textureId!),
            ),
          ),
  );
}
