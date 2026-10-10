import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/host_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider<HostStore>(
      create: (_) => HostStore()..load(),
      child: const MsshApp(),
    ),
  );
}
