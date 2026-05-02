import 'package:flutter/material.dart';
import 'ui/views/server_config_view.dart';

/// Punto de entrada de la aplicación.
void main() {
  runApp(const ProxmoxManagerApp());
}

/// Widget raíz que inicializa tema, navegación y pantalla inicial.
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