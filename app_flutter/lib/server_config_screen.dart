import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';

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
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  String? _keyFilePath;

  String userHomeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    final sshDir = '$userHomeDir/.ssh';
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Seleccionar clave SSH (id_rsa)',
      type: FileType.any,
      allowMultiple: false,
      initialDirectory: sshDir,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _keyFilePath = result.files.single.path);
    }
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

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Configuración SSH',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),

            // Campo: Nombre de la configuración
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la configuración',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 16),

            // Campo: Servidor
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Servidor (IP o URL)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan),
              ),
            ),
            const SizedBox(height: 16),

            // Campo: Puerto
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puerto',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.electrical_services),
              ),
            ),
            const SizedBox(height: 16),

            // Campo: Clave SSH
            InkWell(
              onTap: _pickKeyFile,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Clave privada SSH',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                  suffixIcon: Icon(Icons.folder_open),
                ),
                child: Text(
                  _keyFilePath ?? 'Seleccionar archivo…',
                  style: TextStyle(
                    color: _keyFilePath != null
                        ? Theme.of(context).textTheme.bodyMedium?.color
                        : Colors.black38,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _agregarAFavoritos,
                    icon: Icon(Icons.bookmark_outline, color: Colors.deepPurpleAccent),
                    label: const Text('Agregar a favoritos'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _borrarCampos,
                    icon: Icon(Icons.delete_outline, color: Colors.deepPurpleAccent),
                    label: const Text('Borrar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _conectar,
                    icon: const Icon(Icons.bolt, color: Colors.white),
                    label: const Text('Conectar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Quiero que la función _agregarAFavoritos(), meta el contenido de los textfields y de la ruta a la clave privada, dentro del json que hay en la ruta base del repo
  void _agregarAFavoritos() {
    // Recopilar la info actual del formulario
    final configName = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    final keyPath = _keyFilePath;
    // Validar que no falte ningún campo
    if (configName.isEmpty || host.isEmpty || port.isEmpty || keyPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa todos los campos antes de agregar a favoritos.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // Preparar el objeto de configuración
    final newConfig = {
      'name': configName,
      'host': host,
      'port': port,
      'keyPath': keyPath,
    };
    // Lo guarda en el JSON que hay en la ruta base del repo, llamado 'configuraciones.json'
    final file = File('../configuraciones.json');
    List<dynamic> configs = [];
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      if (content.isNotEmpty) {
        configs = List<dynamic>.from(jsonDecode(content));
      }
    }
    configs.add(newConfig);
    file.writeAsStringSync(jsonEncode(configs));
    // Menaje de éxito
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración agregada a favoritos exitosamente.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        ),
    );
  }

  void _borrarCampos() {}

  void _conectar() {}
}