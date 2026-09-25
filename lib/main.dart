import 'package:flutter/material.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'theme/ncst_theme.dart';

void main() {
  runApp(const NcstGateSecurityApp());
}

class NcstGateSecurityApp extends StatelessWidget {
  const NcstGateSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NCST Gate Security Terminal',
      debugShowCheckedModeBanner: false,
      theme: NcstTheme.lightTheme,
      home: const DashboardScreen(),
    );
  }
}
