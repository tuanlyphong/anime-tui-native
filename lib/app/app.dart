import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'theme.dart';
import '../state/app_controller.dart';
import '../ui/app_shell.dart';

class AnimeTuiApp extends StatelessWidget {
  const AnimeTuiApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Anime TUI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    );
  }
}
