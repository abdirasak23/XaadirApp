// lib/main.dart
import 'package:flutter/material.dart';

import 'Auth/AuthGate.dart';
import 'Auth/AuthWidgets.dart';
import 'Auth/Db_Confi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();
  runApp(const XaadirApp());
}

class XaadirApp extends StatelessWidget {
  const XaadirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xaadir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AuthColors.ink),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const AuthGate(),
    );
  }
}