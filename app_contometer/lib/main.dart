import 'package:flutter/material.dart';

import 'screens/device_scan_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ContometerApp());
}

class ContometerApp extends StatelessWidget {
  const ContometerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contómetros',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const DeviceScanScreen(),
    );
  }
}
