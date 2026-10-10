import 'package:flutter/material.dart';

import 'screens/hosts_screen.dart';
import 'theme.dart';

class MsshApp extends StatelessWidget {
  const MsshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mssh',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HostsScreen(),
    );
  }
}
