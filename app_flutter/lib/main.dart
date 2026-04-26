import 'package:flutter/material.dart';
import 'server_config_screen.dart';

void main() {
  runApp(const ProxmoxManagerApp());
}

class ProxmoxManagerApp extends StatelessWidget {
  const ProxmoxManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestor Proxmox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const ServerConfigScreen(),
    );
  }
}