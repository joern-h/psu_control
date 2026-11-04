import 'package:flutter/material.dart';

import 'src/presets.dart';
import 'src/psu_connection.dart';
import 'src/screens/dashboard.dart';
import 'src/theme.dart';

void main() {
  runApp(
    PsuApp(
      connection: PsuConnection()..start(),
      presets: PresetStore()..load(),
    ),
  );
}

class PsuApp extends StatelessWidget {
  const PsuApp({super.key, required this.connection, required this.presets});

  final PsuConnection connection;
  final PresetStore presets;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PSU Control',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Dashboard(connection: connection, presets: presets),
    );
  }
}
