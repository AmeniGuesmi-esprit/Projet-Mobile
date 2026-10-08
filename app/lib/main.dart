import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/home/main_shell.dart';

void main() {
  runApp(const ProxiLifeApp());
}

class ProxiLifeApp extends StatelessWidget {
  const ProxiLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProxiLife',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const MainShell(),
    );
  }
}
