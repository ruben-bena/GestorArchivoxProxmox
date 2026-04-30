import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:convert';
import 'dart:io';

// ─────────────────────────────────────────────────────────────
// Pantalla raíz — únicamente compone los dos paneles en un Row
// ─────────────────────────────────────────────────────────────
File _getConfigsFile() => File('../configuraciones.json');

List<Map<String, dynamic>> _readSavedConfigs() {
  final file = _getConfigsFile();

  if (!file.existsSync()) {
    return [];
  }

  final content = file.readAsStringSync().trim();
  if (content.isEmpty) {
    return [];
  }

  final decoded = jsonDecode(content);
  if (decoded is! List) {
    return [];
  }

  return decoded
      .whereType<Map>()
      .map((config) => Map<String, dynamic>.from(config))
      .toList();
}

void _writeSavedConfigs(List<Map<String, dynamic>> configs) {
  final file = _getConfigsFile();
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(configs));
}

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final GlobalKey<_ConnectionFormPanelState> _formKey =
      GlobalKey<_ConnectionFormPanelState>();
  List<Map<String, dynamic>> _savedConfigs = [];

  @override
  void initState() {
    super.initState();
    _reloadSavedConfigs();
  }

  void _reloadSavedConfigs() {
    setState(() {
      _savedConfigs = _readSavedConfigs();
    });
  }

  void _selectConfig(Map<String, dynamic> config) {
    _formKey.currentState?.loadConfig(config);
  }

  void _deleteConfig(Map<String, dynamic> config) {
    final configs = _readSavedConfigs();
    configs.removeWhere(
      (savedConfig) =>
          savedConfig['name'] == config['name'] &&
          savedConfig['host'] == config['host'] &&
          savedConfig['port'] == config['port'] &&
          savedConfig['keyPath'] == config['keyPath'],
    );
    _writeSavedConfigs(configs);
    _reloadSavedConfigs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configuración Proxmox")),
      body: Padding(
        padding: EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel izquierdo
            Expanded(
              flex: 2,
              child: SavedConfigsPanel(
                configs: _savedConfigs,
                onConfigSelected: _selectConfig,
                onDeleteConfig: _deleteConfig,
              ),
            ),
            const SizedBox(width: 24),
            // Panel derecho
            Expanded(
              flex: 3,
              child: ConnectionFormPanel(
                key: _formKey,
                onFavoriteAdded: _reloadSavedConfigs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Panel izquierdo — lista de configuraciones guardadas
// ─────────────────────────────────────────────────────────────
class SavedConfigsPanel extends StatelessWidget {
  const SavedConfigsPanel({
    super.key,
    required this.configs,
    required this.onConfigSelected,
    required this.onDeleteConfig,
  });

  final List<Map<String, dynamic>> configs;
  final ValueChanged<Map<String, dynamic>> onConfigSelected;
  final ValueChanged<Map<String, dynamic>> onDeleteConfig;

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
              child: configs.isEmpty
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
                      itemCount: configs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final config = configs[index];

                        return ListTile(
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(config['name']?.toString() ?? ''),
                          onTap: () => onConfigSelected(config),
                          trailing: IconButton(
                            onPressed: () => onDeleteConfig(config),
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.redAccent,
                            tooltip: 'Borrar configuración',
                          ),
                        );
                      },
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
  const ConnectionFormPanel({
    super.key,
    required this.onFavoriteAdded,
  });

  final VoidCallback onFavoriteAdded;

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

  void loadConfig(Map<String, dynamic> config) {
    setState(() {
      _nameController.text = config['name']?.toString() ?? '';
      _hostController.text = config['host']?.toString() ?? '';
      _portController.text = config['port']?.toString() ?? '';
      _keyFilePath = config['keyPath']?.toString();
    });
  }

  void _showFeedbackMessage(
    String message, {
    required bool isSuccess,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final indicatorColor = isSuccess ? Colors.green : Colors.red;

    messenger
      ..hideCurrentSnackBar()
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: Colors.black,
          showCloseIcon: true,
          closeIconColor: theme.colorScheme.onSurface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
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
      _showFeedbackMessage(
        'Completa todos los campos antes de agregar a favoritos.',
        isSuccess: false,
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
    final configs = _readSavedConfigs();
    configs.add(newConfig);
    _writeSavedConfigs(configs);

    widget.onFavoriteAdded();

    // Menaje de éxito
    _showFeedbackMessage(
      'Configuración agregada a favoritos exitosamente.',
      isSuccess: true,
    );
  }

  void _borrarCampos() {
    setState(() {
      _nameController.clear();
      _hostController.clear();
      _portController.clear();
      _keyFilePath = null;
    });
  }

  ({String host, String username, int? port})? _parseSshTarget(String input) {
    final rawValue = input.trim();
    if (rawValue.isEmpty) {
      return null;
    }

    final value = rawValue.contains('://') ? rawValue : 'ssh://$rawValue';
    final parsedUri = Uri.tryParse(value);
    if (parsedUri == null || parsedUri.host.isEmpty) {
      return null;
    }

    final userFromUri = parsedUri.userInfo.isNotEmpty ? parsedUri.userInfo : null;
    final fallbackUser = Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'root';

    return (
      host: parsedUri.host,
      username: userFromUri ?? fallbackUser,
      port: parsedUri.hasPort ? parsedUri.port : null,
    );
  }

  Future<void> _conectar() async {
    final hostOrUri = _hostController.text.trim();
    final formPort = int.tryParse(_portController.text.trim());
    final keyPath = _keyFilePath;

    final target = _parseSshTarget(hostOrUri);

    if (target == null) {
      _showFeedbackMessage(
        'URI/host inválido. Usa por ejemplo: ssh://usuario@servidor:22',
        isSuccess: false,
      );
      return;
    }

    if (keyPath == null || keyPath.trim().isEmpty) {
      _showFeedbackMessage(
        'Selecciona una clave privada SSH antes de conectar.',
        isSuccess: false,
      );
      return;
    }

    final selectedPort = target.port ?? formPort;
    if (selectedPort == null) {
      _showFeedbackMessage(
        'Define el puerto en la URI o en el campo Puerto.',
        isSuccess: false,
      );
      return;
    }

    if (!File(keyPath).existsSync()) {
      _showFeedbackMessage(
        'La clave privada seleccionada no existe.',
        isSuccess: false,
      );
      return;
    }

    SSHClient? client;

    try {
      _showFeedbackMessage(
        'Conectando a ${target.username}@${target.host}:$selectedPort...',
        isSuccess: true,
      );

      final privateKey = await File(keyPath).readAsString();
      final socket = await SSHSocket.connect(target.host, selectedPort, timeout: const Duration(seconds: 10));

      client = SSHClient(
        socket,
        username: target.username,
        identities: SSHKeyPair.fromPem(privateKey),
      );

      final result = await client.run('ls -la');
      final output = utf8.decode(result).trim();

      debugPrint('✅ SSH conectada: ${target.username}@${target.host}:$selectedPort');
      debugPrint('📂 Directorios base del servidor:\n$output');

      _showFeedbackMessage(
        output.isEmpty
            ? 'Conexión SSH correcta (sin salida de ls).'
            : 'Conexión SSH correcta. Revisa consola para ver el listado.',
        isSuccess: true,
      );
    } catch (error) {
      _showFeedbackMessage(
        'Error al conectar por SSH: $error',
        isSuccess: false,
      );
      debugPrint('❌ Error SSH: $error');
    } finally {
      client?.close();
    }
  }
}