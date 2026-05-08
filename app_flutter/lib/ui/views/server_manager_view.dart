import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/managed_remote_server.dart';
import '../../domain/remote_entry.dart';
import '../../services/port_forwarding_service.dart';
import '../../services/remote_entry_format_service.dart';
import '../../services/remote_server_control_service.dart';
import '../../services/sftp_file_service.dart';
import '../widgets/server_manager/explorer_sidebar.dart';
import '../widgets/server_manager/folders_section_panel.dart';
import '../widgets/server_manager/info_row.dart';
import '../widgets/server_manager/managed_servers_section_panel.dart';
import '../widgets/server_manager/remote_entries_content.dart';
import '../widgets/server_manager/visualizer_section_panel.dart';
import '../widgets/shared/feedback_snackbar.dart';
import '../widgets/shared/processing_overlay.dart';

/// Pantalla principal de administración remota (explorador + servidores + visualizador).
class ServerManagerScreen extends StatefulWidget {
  const ServerManagerScreen({
    super.key,
    required this.host,
    required this.username,
    required this.port,
    required this.keyPath,
    this.initialDirectory = '.',
  });

  final String host;
  final String username;
  final int port;
  final String keyPath;
  final String initialDirectory;

  @override
  State<ServerManagerScreen> createState() => _ServerManagerScreenState();
}

class _ServerManagerScreenState extends State<ServerManagerScreen> {
  /// Nombre interno de la sección de gestión de servidores.
  static const String _serversSectionLabel = 'Servidores';

  /// Secciones disponibles en el sidebar de navegación.
  static const List<({String label, IconData icon})> _sections = [
    (label: 'Carpetas', icon: Icons.folder_outlined),
    (label: _serversSectionLabel, icon: Icons.storage_outlined),
    (label: 'Visualizador', icon: Icons.remove_red_eye_outlined),
  ];

  late final SftpFileService _sftpService;
  late final RemoteServerControlService _serverControlService;
  late final PortForwardingService _portForwardingService;
  final RemoteEntryFormatService _formatService =
      const RemoteEntryFormatService();

  List<RemoteEntry> _entries = const [];
  List<ManagedRemoteServer> _managedServers = const [];
  String _selectedSection = 'Carpetas';
  String _currentDirectory = '.';
  bool _isLoading = true;
  bool _isLoadingManagedServers = true;
  bool _isProcessing = false;
  String _processingLabel = 'Procesando...';
  String? _errorMessage;
  String? _managedServersErrorMessage;
  int _managedServersRequestId = 0;
  int _serverDiscoveryDepth = 1;

  @override
  void initState() {
    super.initState();
    _sftpService = SftpFileService(
      host: widget.host,
      username: widget.username,
      port: widget.port,
      keyPath: widget.keyPath,
    );
    _serverControlService = RemoteServerControlService(
      host: widget.host,
      username: widget.username,
      port: widget.port,
      keyPath: widget.keyPath,
    );
    _portForwardingService = PortForwardingService();
    _loadDirectory(widget.initialDirectory);
  }

  @override
  void dispose() {
    _portForwardingService.dispose();
    super.dispose();
  }

  /// Indica si el usuario se encuentra en la raíz remota.
  bool get _isRootDirectory => _currentDirectory == '/';

  /// Carga un directorio remoto y sincroniza la detección de servidores.
  Future<void> _loadDirectory(String directory) async {
    setState(() {
      _isLoading = true;
      _isLoadingManagedServers = true;
      _errorMessage = null;
      _managedServersErrorMessage = null;
    });

    try {
      final snapshot = await _sftpService.loadDirectory(directory);

      if (!mounted) {
        return;
      }

      setState(() {
        _currentDirectory = snapshot.directory;
        _entries = snapshot.entries;
        _isLoading = false;
      });

      await _refreshManagedServers(
        directory: snapshot.directory,
        entries: snapshot.entries,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'No se pudo cargar el contenido remoto: $error';
        _entries = const [];
        _isLoading = false;
        _managedServers = const [];
        _isLoadingManagedServers = false;
        _managedServersErrorMessage =
            'No se pudo detectar la lista de servidores.';
      });
    }
  }

  /// Refresca la lista de servidores administrables para el directorio actual.
  Future<void> _refreshManagedServers({
    String? directory,
    List<RemoteEntry>? entries,
  }) async {
    final requestId = ++_managedServersRequestId;
    final targetDirectory = directory ?? _currentDirectory;
    final targetEntries = entries ?? _entries;

    setState(() {
      _isLoadingManagedServers = true;
      _managedServersErrorMessage = null;
    });

    try {
      final servers = await _serverControlService.discoverServers(
        currentDirectory: targetDirectory,
        entries: targetEntries,
        searchDepth: _serverDiscoveryDepth,
      );
      await _portForwardingService.syncSessions();

      if (!mounted || requestId != _managedServersRequestId) {
        return;
      }

      setState(() {
        _managedServers = _mergePortForwardSessions(servers);
        _isLoadingManagedServers = false;
      });
    } catch (error) {
      if (!mounted || requestId != _managedServersRequestId) {
        return;
      }

      setState(() {
        _managedServers = const [];
        _isLoadingManagedServers = false;
        _managedServersErrorMessage =
            'No se pudieron detectar los servidores remotos: $error';
      });
    }
  }

  /// Mezcla estado de túneles activos en la lista de servidores detectados.
  List<ManagedRemoteServer> _mergePortForwardSessions(
    List<ManagedRemoteServer> servers,
  ) {
    final sessions = _portForwardingService.sessionsByServerPath;

    return servers
        .map((server) {
          final session = sessions[server.fullPath];
          if (session == null) {
            return server.copyWith(
              clearForwardedLocalPort: true,
              clearForwardedRemotePort: true,
            );
          }

          return server.copyWith(
            forwardedLocalPort: session.localPort,
            forwardedRemotePort: session.remotePort,
          );
        })
        .toList(growable: false);
  }

  /// Ejecuta una acción bloqueante mostrando overlay de progreso.
  Future<void> _runProcessingAction(
    String label,
    Future<void> Function() action,
  ) async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingLabel = label;
    });

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Navega al directorio padre del path remoto actual.
  void _openParentDirectory() {
    if (_isRootDirectory) {
      return;
    }

    final normalizedPath =
        _currentDirectory.endsWith('/') && _currentDirectory.length > 1
        ? _currentDirectory.substring(0, _currentDirectory.length - 1)
        : _currentDirectory;
    final lastSlashIndex = normalizedPath.lastIndexOf('/');
    final parentDirectory = lastSlashIndex <= 0
        ? '/'
        : normalizedPath.substring(0, lastSlashIndex);

    _loadDirectory(parentDirectory);
  }

  /// Navega al subdirectorio seleccionado.
  void _openChildDirectory(RemoteEntry entry) {
    _loadDirectory(entry.fullPath);
  }

  /// Muestra diálogo para solicitar nuevo nombre de una entrada remota.
  Future<String?> _showRenameDialog(RemoteEntry entry) async {
    final controller = TextEditingController(text: entry.name);

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F1F),
          title: const Text('Cambiar nombre'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nuevo nombre',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  /// Solicita confirmación antes de borrar una entrada remota.
  Future<bool> _showDeleteConfirmation(RemoteEntry entry) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F1F),
          title: const Text('Borrar elemento'),
          content: Text(
            '¿Seguro que quieres borrar ${entry.isDirectory ? 'la carpeta' : 'el archivo'} "${entry.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Borrar'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  /// Enruta la acción de menú contextual a su manejador específico.
  Future<void> _handleEntryAction(EntryAction action, RemoteEntry entry) async {
    switch (action) {
      case EntryAction.rename:
        await _renameEntry(entry);
        break;
      case EntryAction.download:
        await _downloadEntry(entry);
        break;
      case EntryAction.extractZip:
        await _extractZipEntry(entry);
        break;
      case EntryAction.delete:
        await _deleteEntry(entry);
        break;
      case EntryAction.info:
        await _showEntryInfo(entry);
        break;
    }
  }

  /// Renombra una entrada remota y refresca el directorio.
  Future<void> _renameEntry(RemoteEntry entry) async {
    final newName = await _showRenameDialog(entry);
    if (newName == null || newName.isEmpty || newName == entry.name) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (newName.contains('/')) {
      showFeedbackSnackbar(
        context,
        'El nombre no puede contener "/".',
        isSuccess: false,
        durationSeconds: 3,
      );
      return;
    }

    await _runProcessingAction('Cambiando nombre...', () async {
      try {
        await _sftpService.rename(
          currentDirectory: _currentDirectory,
          entry: entry,
          newName: newName,
        );
        await _loadDirectory(_currentDirectory);
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Nombre actualizado correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo cambiar el nombre: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  /// Borra una entrada remota tras confirmación del usuario.
  Future<void> _deleteEntry(RemoteEntry entry) async {
    final confirmed = await _showDeleteConfirmation(entry);
    if (!confirmed) {
      return;
    }

    await _runProcessingAction('Borrando elemento...', () async {
      try {
        await _sftpService.deleteEntry(entry);
        await _loadDirectory(_currentDirectory);
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Elemento borrado correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo borrar el elemento: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  /// Descarga una entrada remota a una carpeta local seleccionada.
  Future<void> _downloadEntry(RemoteEntry entry) async {
    final localDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar destino local',
      lockParentWindow: true,
    );

    if (localDirectory == null || localDirectory.trim().isEmpty) {
      return;
    }

    await _runProcessingAction('Descargando elemento...', () async {
      try {
        await _sftpService.downloadEntry(
          entry: entry,
          localDirectory: localDirectory,
        );
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Descarga completada en local.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo descargar el elemento: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  /// Ejecuta descompresión remota de archivo ZIP.
  Future<void> _extractZipEntry(RemoteEntry entry) async {
    await _runProcessingAction('Descomprimiendo archivo ZIP...', () async {
      try {
        await _sftpService.extractZipEntry(entry);
        await _loadDirectory(_currentDirectory);
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Archivo ZIP descomprimido correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo descomprimir el ZIP: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  /// Recupera y muestra metadatos detallados de una entrada remota.
  Future<void> _showEntryInfo(RemoteEntry entry) async {
    await _runProcessingAction('Cargando información...', () async {
      try {
        final latestEntry = await _sftpService.getEntryInfo(entry);

        if (!mounted) {
          return;
        }

        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F1F1F),
              title: const Text('Información'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InfoRow(label: 'Nombre', value: latestEntry.name),
                    InfoRow(label: 'Ruta', value: latestEntry.fullPath),
                    InfoRow(label: 'Tipo', value: latestEntry.typeLabel),
                    InfoRow(
                      label: 'Permisos',
                      value:
                          '${_formatService.formatPermissionString(latestEntry.modeValue)} (${_formatService.formatPermissionOctal(latestEntry.modeValue)})',
                    ),
                    InfoRow(
                      label: 'Tamaño',
                      value: _formatService.formatSize(latestEntry.size),
                    ),
                    InfoRow(
                      label: 'Última modificación',
                      value: _formatService.formatUnixTime(
                        latestEntry.modifyTime,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo obtener la información del elemento: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  /// Arranca un servidor remoto detectado y refresca estado.
  Future<void> _startManagedServer(ManagedRemoteServer server) async {
    await _runProcessingAction('Arrancando servidor...', () async {
      try {
        await _serverControlService.startServer(server);
        await Future<void>.delayed(const Duration(seconds: 2));
        await _refreshManagedServers();
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Servidor ${server.name} arrancado correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo arrancar ${server.name}: $error',
          isSuccess: false,
          durationSeconds: 4,
        );
      }
    });
  }

  /// Detiene un servidor remoto detectado y refresca estado.
  Future<void> _stopManagedServer(ManagedRemoteServer server) async {
    await _runProcessingAction('Parando servidor...', () async {
      try {
        await _serverControlService.stopServer(server);
        await _refreshManagedServers();
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Servidor ${server.name} detenido correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo detener ${server.name}: $error',
          isSuccess: false,
          durationSeconds: 4,
        );
      }
    });
  }

  /// Reinicia un servidor remoto detectado y refresca estado.
  Future<void> _restartManagedServer(ManagedRemoteServer server) async {
    await _runProcessingAction('Reiniciando servidor...', () async {
      try {
        await _serverControlService.restartServer(server);
        await Future<void>.delayed(const Duration(seconds: 2));
        await _refreshManagedServers();
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Servidor ${server.name} reiniciado correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo reiniciar ${server.name}: $error',
          isSuccess: false,
          durationSeconds: 4,
        );
      }
    });
  }

  /// Abre un túnel SSH local→remoto para el puerto de un servidor.
  Future<void> _redirectServerPort(ManagedRemoteServer server) async {
    final selectedPorts = await _showPortRedirectDialog(server);
    if (selectedPorts == null) {
      return;
    }

    await _runProcessingAction('Abriendo túnel SSH...', () async {
      try {
        final session = await _portForwardingService.startPortForward(
          serverPath: server.fullPath,
          host: widget.host,
          username: widget.username,
          sshPort: widget.port,
          keyPath: widget.keyPath,
          remotePort: selectedPorts.remotePort,
          localPort: selectedPorts.localPort,
        );
        await _refreshManagedServers();
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Puerto remoto ${session.remotePort} disponible en localhost:${session.localPort}.',
          isSuccess: true,
          durationSeconds: 4,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo redirigir el puerto de ${server.name}: $error',
          isSuccess: false,
          durationSeconds: 4,
        );
      }
    });
  }

  /// Cierra el túnel SSH activo asociado a un servidor.
  Future<void> _closePortRedirect(ManagedRemoteServer server) async {
    await _runProcessingAction('Cerrando túnel SSH...', () async {
      try {
        await _portForwardingService.stopPortForward(server.fullPath);
        await _refreshManagedServers();
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Redirección cerrada para ${server.name}.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo cerrar la redirección: $error',
          isSuccess: false,
          durationSeconds: 4,
        );
      }
    });
  }

  /// Diálogo para capturar puertos local/remoto de una redirección SSH.
  Future<({int localPort, int remotePort})?> _showPortRedirectDialog(
    ManagedRemoteServer server,
  ) async {
    final currentSession =
        _portForwardingService.sessionsByServerPath[server.fullPath];
    final localPortController = TextEditingController(
      text: (currentSession?.localPort ?? server.detectedPort).toString(),
    );
    final remotePortController = TextEditingController(
      text: (currentSession?.remotePort ?? server.detectedPort).toString(),
    );

    final result = await showDialog<({int localPort, int remotePort})>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F1F),
          title: Text('Redirigir puerto de ${server.name}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: remotePortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Puerto remoto',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: localPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Puerto local',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'El túnel expondrá el servicio remoto en localhost usando SSH.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final localPort = int.tryParse(localPortController.text.trim());
                final remotePort = int.tryParse(
                  remotePortController.text.trim(),
                );

                if (!_isValidPort(localPort) || !_isValidPort(remotePort)) {
                  showFeedbackSnackbar(
                    context,
                    'Introduce puertos válidos entre 1 y 65535.',
                    isSuccess: false,
                    durationSeconds: 3,
                  );
                  return;
                }

                Navigator.of(
                  context,
                ).pop((localPort: localPort!, remotePort: remotePort!));
              },
              child: const Text('Redirigir'),
            ),
          ],
        );
      },
    );

    localPortController.dispose();
    remotePortController.dispose();
    return result;
  }

  /// Valida rango de puertos TCP.
  bool _isValidPort(int? value) {
    return value != null && value >= 1 && value <= 65535;
  }

  /// Actualiza la profundidad de escaneo de servidores y relanza detección.
  void _updateServerDiscoveryDepth(int depth) {
    final normalizedDepth = depth.clamp(0, 10).toInt();
    if (normalizedDepth == _serverDiscoveryDepth) {
      return;
    }

    setState(() {
      _serverDiscoveryDepth = normalizedDepth;
    });

    _refreshManagedServers();
  }

  /// Muestra opciones para subir archivos o carpeta.
  Future<void> _showUploadOptions() async {
    final action = await showModalBottomSheet<_UploadAction>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.upload_file,
                  color: Colors.deepPurpleAccent,
                ),
                title: const Text('Subir archivos'),
                onTap: () => Navigator.of(context).pop(_UploadAction.files),
              ),
              ListTile(
                leading: const Icon(
                  Icons.create_new_folder_outlined,
                  color: Colors.deepPurpleAccent,
                ),
                title: const Text('Subir carpeta'),
                onTap: () => Navigator.of(context).pop(_UploadAction.directory),
              ),
            ],
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    if (action == _UploadAction.files) {
      await _uploadFiles();
      return;
    }

    await _uploadDirectory();
  }

  /// Sube múltiples archivos locales al directorio remoto actual.
  Future<void> _uploadFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      lockParentWindow: true,
      dialogTitle: 'Seleccionar archivos para subir',
    );

    final paths =
        result?.files.map((file) => file.path).whereType<String>().toList() ??
        const <String>[];

    if (paths.isEmpty) {
      return;
    }

    await _runProcessingAction('Subiendo archivos...', () async {
      try {
        await _sftpService.uploadFiles(
          currentDirectory: _currentDirectory,
          localPaths: paths,
        );
        await _loadDirectory(_currentDirectory);
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Archivos subidos correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudieron subir los archivos: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  /// Sube una carpeta local completa al directorio remoto actual.
  Future<void> _uploadDirectory() async {
    final localDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta para subir',
      lockParentWindow: true,
    );

    if (localDirectory == null || localDirectory.trim().isEmpty) {
      return;
    }

    await _runProcessingAction('Subiendo carpeta...', () async {
      try {
        await _sftpService.uploadDirectory(
          currentDirectory: _currentDirectory,
          localDirectory: localDirectory,
        );
        await _loadDirectory(_currentDirectory);
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'Carpeta subida correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFeedbackSnackbar(
          context,
          'No se pudo subir la carpeta: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  /// Selecciona panel derecho según sección activa.
  Widget _buildRightPanel() {
    switch (_selectedSection) {
      case 'Carpetas':
        return FoldersSectionPanel(
          currentDirectory: _currentDirectory,
          isLoading: _isLoading,
          isRootDirectory: _isRootDirectory,
          errorMessage: _errorMessage,
          entries: _entries,
          onUpload: _showUploadOptions,
          onGoParent: _openParentDirectory,
          onRefresh: () => _loadDirectory(_currentDirectory),
          onRetry: () => _loadDirectory(_currentDirectory),
          onOpenDirectory: _openChildDirectory,
          onActionSelected: _handleEntryAction,
        );
      case _serversSectionLabel:
        return ManagedServersSectionPanel(
          currentDirectory: _currentDirectory,
          isLoading: _isLoadingManagedServers,
          errorMessage: _managedServersErrorMessage,
          servers: _managedServers,
          discoveryDepth: _serverDiscoveryDepth,
          onRefresh: _refreshManagedServers,
          onRetry: _refreshManagedServers,
          onDiscoveryDepthChanged: _updateServerDiscoveryDepth,
          onStartServer: _startManagedServer,
          onStopServer: _stopManagedServer,
          onRestartServer: _restartManagedServer,
          onRedirectPort: _redirectServerPort,
          onStopRedirect: _closePortRedirect,
        );
      case 'Visualizador':
        return VisualizerSectionPanel(
          currentDirectory: _currentDirectory,
          isLoading: _isLoading,
          isRootDirectory: _isRootDirectory,
          errorMessage: _errorMessage,
          entries: _entries,
          onUpload: _showUploadOptions,
          onGoParent: _openParentDirectory,
          onRefresh: () => _loadDirectory(_currentDirectory),
          onRetry: () => _loadDirectory(_currentDirectory),
          onOpenDirectory: _openChildDirectory,
          onActionSelected: _handleEntryAction,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestor de archivos Proxmox')),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isProcessing,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: ExplorerSidebar(
                      sections: _sections,
                      selectedSection: _selectedSection,
                      onSectionSelected: (section) {
                        setState(() {
                          _selectedSection = section;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(flex: 3, child: _buildRightPanel()),
                ],
              ),
            ),
          ),
          if (_isProcessing) ProcessingOverlay(label: _processingLabel),
        ],
      ),
    );
  }
}

enum _UploadAction { files, directory }
