import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// Pantalla raíz — únicamente compone los dos paneles en un Row
// ─────────────────────────────────────────────────────────────
class ServerConfigScreen extends StatelessWidget {
  const ServerConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configuración Proxmox")),
      body: const Padding(
        padding: EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel izquierdo
            Expanded(flex: 2, child: SavedConfigsPanel()),
            SizedBox(width: 24),
            // Panel derecho
            Expanded(flex: 3, child: ConnectionFormPanel()),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Panel izquierdo — lista de configuraciones guardadas
// ─────────────────────────────────────────────────────────────
class SavedConfigsPanel extends StatefulWidget {
  const SavedConfigsPanel({super.key});

  @override
  State<SavedConfigsPanel> createState() => _SavedConfigsPanelState();
}

class _SavedConfigsPanelState extends State<SavedConfigsPanel> {
  // Aquí irá la lista de configuraciones guardadas en el futuro
  final List<String> _configs = [];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera
            const Row(
              children: [
                Icon(Icons.bookmark_outline, color: Colors.deepPurpleAccent),
                SizedBox(width: 8),
                Text(
                  "Configuraciones guardadas",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // Contenido
            Expanded(
              child: _configs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.black26),
                          SizedBox(height: 12),
                          Text(
                            "Aún no hay configuraciones guardadas",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black38),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _configs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: Text(_configs[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Panel derecho — formulario de conexión SSH
// ─────────────────────────────────────────────────────────────
class ConnectionFormPanel extends StatefulWidget {
  const ConnectionFormPanel({super.key});

  @override
  State<ConnectionFormPanel> createState() => _ConnectionFormPanelState();
}

class _ConnectionFormPanelState extends State<ConnectionFormPanel> {
  final _hostController = TextEditingController(text: "ieticloudpro.ieti.cat");
  final _userController = TextEditingController(text: "usuario");
  final _portController = TextEditingController(text: "22");

  @override
  void dispose() {
    _hostController.dispose();
    _userController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dns, size: 80, color: Colors.deepPurpleAccent),
            const SizedBox(height: 32),

            // Campo: Host
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Dirección IP o Host',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan),
              ),
            ),
            const SizedBox(height: 16),

            // Campo: Usuario
            TextField(
              controller: _userController,
              decoration: const InputDecoration(
                labelText: 'Usuario SSH',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 24),

            // Botón de Conectar
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.bolt),
                label: const Text(
                  "CONECTAR AL SERVIDOR",
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: _intentarConexion,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _intentarConexion() {
    // TODO
  }
}