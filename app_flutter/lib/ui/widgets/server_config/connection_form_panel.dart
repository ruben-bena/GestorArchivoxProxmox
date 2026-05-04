import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../domain/server_connection_config.dart';
import '../../../services/config_storage_service.dart';
import '../../../services/ssh_connection_service.dart';
import '../../views/server_manager_view.dart';
import '../shared/feedback_snackbar.dart';

/// Formulario de conexión SSH con soporte de favoritos y validaciones básicas.
class ConnectionFormPanel extends StatefulWidget {
  const ConnectionFormPanel({
    super.key,
    required this.onFavoriteAdded,
    required this.onConnectingStateChanged,
    required this.configStorageService,
    required this.sshConnectionService,
  });

  final VoidCallback onFavoriteAdded;
  final ValueChanged<bool> onConnectingStateChanged;
  final ConfigStorageService configStorageService;
  final SshConnectionService sshConnectionService;

  @override
  State<ConnectionFormPanel> createState() => ConnectionFormPanelState();
}

class ConnectionFormPanelState extends State<ConnectionFormPanel> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  String? _keyFilePath;

  final String _userHomeDir =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  /// Abre selector de archivos para elegir la clave privada SSH.
  Future<void> _pickKeyFile() async {
    final sshDir = '$_userHomeDir/.ssh';
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Seleccionar clave SSH (id_rsa)',
      type: FileType.any,
      allowMultiple: false,
      initialDirectory: sshDir,
    );
    // Solo actualiza el estado cuando el usuario confirma una ruta válida.
    if (result != null && result.files.single.path != null) {
      setState(() => _keyFilePath = result.files.single.path);
    }
  }

  /// Carga en los campos la configuración seleccionada por el usuario.
  void loadConfig(ServerConnectionConfig config) {
    setState(() {
      _nameController.text = config.name;
      _hostController.text = config.host;
      _portController.text = config.port;
      _keyFilePath = config.keyPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 424),
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
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la configuración',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Servidor (IP o URL)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lan),
                ),
              ),
              const SizedBox(height: 16),
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
                      icon: const Icon(
                        Icons.bookmark_outline,
                        color: Colors.deepPurpleAccent,
                      ),
                      label: const Text('Agregar a favoritos'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _borrarCampos,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.deepPurpleAccent,
                      ),
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
      ),
    );
  }

  /// Persiste la configuración actual como favorita.
  void _agregarAFavoritos() {
    final configName = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    final keyPath = _keyFilePath;

    // Validación mínima para evitar persistir configuraciones incompletas.
    if (configName.isEmpty || host.isEmpty || port.isEmpty || keyPath == null) {
      showFeedbackSnackbar(
        context,
        'Completa todos los campos antes de agregar a favoritos.',
        isSuccess: false,
      );
      return;
    }

    final newConfig = ServerConnectionConfig(
      name: configName,
      host: host,
      port: port,
      keyPath: keyPath,
    );

    widget.configStorageService.add(newConfig);
    widget.onFavoriteAdded();

    showFeedbackSnackbar(
      context,
      'Configuración agregada a favoritos exitosamente.',
      isSuccess: true,
    );
  }

  /// Limpia todos los campos del formulario.
  void _borrarCampos() {
    setState(() {
      _nameController.clear();
      _hostController.clear();
      _portController.clear();
      _keyFilePath = null;
    });
  }

  /// Valida credenciales SSH y navega a la pantalla de gestión remota.
  Future<void> _conectar() async {
    final hostOrUri = _hostController.text.trim();
    final formPort = int.tryParse(_portController.text.trim());
    final keyPath = _keyFilePath;
    var connectionSucceeded = false;

    final parsedTarget = widget.sshConnectionService.parseTarget(hostOrUri);

    // 1) Validar host/URI antes de continuar con operaciones de disco/red.
    if (parsedTarget == null) {
      showFeedbackSnackbar(
        context,
        'URI/host inválido. Usa por ejemplo: ssh://usuario@servidor:22',
        isSuccess: false,
      );
      return;
    }

    // 2) Exigir clave privada explícita para autenticación SSH.
    if (keyPath == null || keyPath.trim().isEmpty) {
      showFeedbackSnackbar(
        context,
        'Selecciona una clave privada SSH antes de conectar.',
        isSuccess: false,
      );
      return;
    }

    // 3) Resolver puerto final: prioridad al que venga en la URI, luego formulario.
    final selectedPort = parsedTarget.port ?? formPort;
    if (selectedPort == null) {
      showFeedbackSnackbar(
        context,
        'Define el puerto en la URI o en el campo Puerto.',
        isSuccess: false,
      );
      return;
    }

    final target = parsedTarget.copyWith(port: selectedPort);

    // 4) Fallar rápido si la ruta de clave ya no existe en el sistema local.
    if (!File(keyPath).existsSync()) {
      showFeedbackSnackbar(
        context,
        'La clave privada seleccionada no existe.',
        isSuccess: false,
      );
      return;
    }

    try {
      widget.onConnectingStateChanged(true);
      showFeedbackSnackbar(
        context,
        'Conectando a ${target.username}@${target.host}:$selectedPort...',
        isSuccess: true,
      );

      // Healthcheck remoto: valida credenciales, conectividad y permisos básicos.
      final output = await widget.sshConnectionService.runHealthcheck(
        target: target,
        keyPath: keyPath,
      );

      debugPrint(
        '✅ SSH conectada: ${target.username}@${target.host}:$selectedPort',
      );
      debugPrint('📂 Directorios base del servidor:\n$output');

      if (!mounted) {
        return;
      }

      showFeedbackSnackbar(
        context,
        output.isEmpty
            ? 'Conexión SSH correcta (sin salida de ls).'
            : 'Conexión SSH correcta. Revisa consola para ver el listado.',
        isSuccess: true,
      );
      connectionSucceeded = true;
    } catch (error) {
      if (!mounted) {
        return;
      }

      showFeedbackSnackbar(
        context,
        'Error al conectar por SSH: $error',
        isSuccess: false,
      );
      debugPrint('❌ Error SSH: $error');
    } finally {
      // Garantiza limpieza visual incluso cuando hay error o retorno temprano.
      widget.onConnectingStateChanged(false);
    }

    // La navegación solo ocurre si la prueba SSH fue correcta y el widget sigue montado.
    if (connectionSucceeded && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ServerManagerScreen(
            host: target.host,
            username: target.username,
            port: selectedPort,
            keyPath: keyPath,
          ),
        ),
      );
    }
  }
}
