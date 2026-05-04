import 'package:flutter/material.dart';
import 'ui/views/server_config_view.dart';

/// Punto de entrada de la aplicación.
void main() {
  // Inicializa todo el árbol de widgets con el contenedor raíz de la app.
  runApp(const ProxmoxManagerApp());
}

/// Widget raíz que inicializa tema, navegación y pantalla inicial.
class ProxmoxManagerApp extends StatelessWidget {
  const ProxmoxManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Metadatos y ajustes base globales de navegación/tema.
      title: 'Gestor Proxmox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      // Pantalla de entrada para configurar conexión SSH inicial.
      home: const ServerConfigScreen(),
    );
  }
}