import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/remote_entry.dart';
import '../../services/remote_entry_format_service.dart';
import '../../services/sftp_file_service.dart';
import '../widgets/server_manager/explorer_sidebar.dart';
import '../widgets/server_manager/folders_section_panel.dart';
import '../widgets/server_manager/info_row.dart';
import '../widgets/server_manager/remote_entries_content.dart';
import '../widgets/server_manager/section_placeholder_panel.dart';
import '../widgets/server_manager/visualizer_section_panel.dart';
import '../widgets/shared/feedback_snackbar.dart';
import '../widgets/shared/processing_overlay.dart';

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
  static const List<({String label, IconData icon})> _sections = [
    (label: 'Carpetas', icon: Icons.folder_outlined),
    (label: 'Servidores Java/NodeJS', icon: Icons.storage_outlined),
    (label: 'Visualizador', icon: Icons.remove_red_eye_outlined),
  ];

  late final SftpFileService _sftpService;
  final RemoteEntryFormatService _formatService =
      const RemoteEntryFormatService();

  List<RemoteEntry> _entries = const [];
  String _selectedSection = 'Carpetas';
  String _currentDirectory = '.';
  bool _isLoading = true;
  bool _isProcessing = false;
  String _processingLabel = 'Procesando...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sftpService = SftpFileService(
      host: widget.host,
      username: widget.username,
      port: widget.port,
      keyPath: widget.keyPath,
    );
    _loadDirectory(widget.initialDirectory);
  }

  bool get _isRootDirectory => _currentDirectory == '/';

  Future<void> _loadDirectory(String directory) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshot = await _sftpService.loadDirectory(directory);
      List<RemoteEntry> resolvedEntries = snapshot.entries;

      try {
        resolvedEntries = await _sftpService.resolveEntriesWithContentSize(
          snapshot.entries,
        );
      } catch (_) {}

      if (!mounted) {
        return;
      }

      setState(() {
        _currentDirectory = snapshot.directory;
        _entries = resolvedEntries;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'No se pudo cargar el contenido remoto: $error';
        _entries = const [];
        _isLoading = false;
      });
    }
  }

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

  void _openChildDirectory(RemoteEntry entry) {
    _loadDirectory(entry.fullPath);
  }

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

  Future<void> _handleEntryAction(EntryAction action, RemoteEntry entry) async {
    switch (action) {
      case EntryAction.rename:
        await _renameEntry(entry);
        break;
      case EntryAction.download:
        await _downloadEntry(entry);
        break;
      case EntryAction.delete:
        await _deleteEntry(entry);
        break;
      case EntryAction.info:
        await _showEntryInfo(entry);
        break;
    }
  }

  Future<void> _renameEntry(RemoteEntry entry) async {
    final newName = await _showRenameDialog(entry);
    if (newName == null || newName.isEmpty || newName == entry.name) {
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
        showFeedbackSnackbar(
          context,
          'Nombre actualizado correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        showFeedbackSnackbar(
          context,
          'No se pudo cambiar el nombre: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

  Future<void> _deleteEntry(RemoteEntry entry) async {
    final confirmed = await _showDeleteConfirmation(entry);
    if (!confirmed) {
      return;
    }

    await _runProcessingAction('Borrando elemento...', () async {
      try {
        await _sftpService.deleteEntry(entry);
        await _loadDirectory(_currentDirectory);
        showFeedbackSnackbar(
          context,
          'Elemento borrado correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        showFeedbackSnackbar(
          context,
          'No se pudo borrar el elemento: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

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
        showFeedbackSnackbar(
          context,
          'Descarga completada en local.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        showFeedbackSnackbar(
          context,
          'No se pudo descargar el elemento: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

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
              title: const Text('Información y permisos'),
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
                      label: 'Usuario propietario',
                      value:
                          _formatService.extractOwnerFromLongName(
                            latestEntry.longName,
                          ) ??
                          (latestEntry.userId?.toString() ?? 'No disponible'),
                    ),
                    InfoRow(
                      label: 'Grupo propietario',
                      value:
                          _formatService.extractGroupFromLongName(
                            latestEntry.longName,
                          ) ??
                          (latestEntry.groupId?.toString() ?? 'No disponible'),
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
                    InfoRow(
                      label: 'Detalle remoto',
                      value: latestEntry.longName.isEmpty
                          ? 'No disponible'
                          : latestEntry.longName,
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
        showFeedbackSnackbar(
          context,
          'No se pudo obtener la información del elemento: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

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
        showFeedbackSnackbar(
          context,
          'Archivos subidos correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        showFeedbackSnackbar(
          context,
          'No se pudieron subir los archivos: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

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
        showFeedbackSnackbar(
          context,
          'Carpeta subida correctamente.',
          isSuccess: true,
          durationSeconds: 3,
        );
      } catch (error) {
        showFeedbackSnackbar(
          context,
          'No se pudo subir la carpeta: $error',
          isSuccess: false,
          durationSeconds: 3,
        );
      }
    });
  }

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
        return const SectionPlaceholderPanel(
          title: 'Servidores Java/NodeJS',
          icon: Icons.storage_outlined,
          message: 'Panel reservado para próximos módulos.',
        );
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
