import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
    (label: 'Recientes', icon: Icons.history),
    (label: 'Carpetas', icon: Icons.folder_outlined),
    (label: 'Compartidos', icon: Icons.group_outlined),
    (label: 'Eliminados', icon: Icons.delete_outline),
  ];

  List<_RemoteEntry> _entries = const [];
  String _selectedSection = 'Carpetas';
  String _currentDirectory = '.';
  bool _isLoading = true;
  bool _isProcessing = false;
  String _processingLabel = 'Procesando...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDirectory(widget.initialDirectory);
  }

  Future<SSHClient> _createSshClient() async {
    final privateKey = await File(widget.keyPath).readAsString();
    final socket = await SSHSocket.connect(
      widget.host,
      widget.port,
      timeout: const Duration(seconds: 10),
    );

    return SSHClient(
      socket,
      username: widget.username,
      identities: SSHKeyPair.fromPem(privateKey),
    );
  }

  Future<T> _withSftp<T>(
    Future<T> Function(SftpClient sftp, SSHClient client) action,
  ) async {
    final client = await _createSshClient();

    try {
      final sftp = await client.sftp();
      try {
        return await action(sftp, client);
      } finally {
        sftp.close();
      }
    } finally {
      client.close();
    }
  }

  Future<void> _loadDirectory(String directory) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _withSftp((sftp, client) async {
        final resolvedDirectory = await sftp.absolute(directory);
        final names = await sftp.listdir(resolvedDirectory);

        final entries =
            names
                .where((name) => name.filename != '.' && name.filename != '..')
                .map(
                  (name) => _RemoteEntry.fromSftpName(
                    parentDirectory: resolvedDirectory,
                    name: name,
                  ),
                )
                .toList()
              ..sort((a, b) {
                if (a.isDirectory != b.isDirectory) {
                  return a.isDirectory ? -1 : 1;
                }

                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });

        return (directory: resolvedDirectory, entries: entries);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _currentDirectory = result.directory;
        _entries = result.entries;
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

  void _showFeedbackMessage(String message, {required bool isSuccess}) {
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
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.black,
          showCloseIcon: true,
          closeIconColor: theme.colorScheme.onSurface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
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

  String _joinRemotePath(String parent, String child) {
    if (parent == '/') {
      return '/$child';
    }

    return '$parent/$child';
  }

  String _joinLocalPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }

    return '$parent${Platform.pathSeparator}$child';
  }

  String _localBasename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  bool get _isRootDirectory => _currentDirectory == '/';

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

  void _openChildDirectory(_RemoteEntry entry) {
    _loadDirectory(entry.fullPath);
  }

  Future<String?> _showRenameDialog(_RemoteEntry entry) async {
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

  Future<bool> _showDeleteConfirmation(_RemoteEntry entry) async {
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

  Future<void> _handleEntryAction(
    _EntryAction action,
    _RemoteEntry entry,
  ) async {
    switch (action) {
      case _EntryAction.rename:
        await _renameEntry(entry);
        break;
      case _EntryAction.download:
        await _downloadEntry(entry);
        break;
      case _EntryAction.delete:
        await _deleteEntry(entry);
        break;
      case _EntryAction.info:
        await _showEntryInfo(entry);
        break;
    }
  }

  Future<void> _renameEntry(_RemoteEntry entry) async {
    final newName = await _showRenameDialog(entry);
    if (newName == null || newName.isEmpty || newName == entry.name) {
      return;
    }

    if (newName.contains('/')) {
      _showFeedbackMessage(
        'El nombre no puede contener "/".',
        isSuccess: false,
      );
      return;
    }

    final newPath = _joinRemotePath(_currentDirectory, newName);

    await _runProcessingAction('Cambiando nombre...', () async {
      try {
        await _withSftp((sftp, client) => sftp.rename(entry.fullPath, newPath));
        await _loadDirectory(_currentDirectory);
        _showFeedbackMessage(
          'Nombre actualizado correctamente.',
          isSuccess: true,
        );
      } catch (error) {
        _showFeedbackMessage(
          'No se pudo cambiar el nombre: $error',
          isSuccess: false,
        );
      }
    });
  }

  Future<void> _deleteEntry(_RemoteEntry entry) async {
    final confirmed = await _showDeleteConfirmation(entry);
    if (!confirmed) {
      return;
    }

    await _runProcessingAction('Borrando elemento...', () async {
      try {
        await _withSftp((sftp, client) async {
          await _deleteRemoteEntryRecursive(sftp, entry.fullPath);
        });
        await _loadDirectory(_currentDirectory);
        _showFeedbackMessage(
          'Elemento borrado correctamente.',
          isSuccess: true,
        );
      } catch (error) {
        _showFeedbackMessage(
          'No se pudo borrar el elemento: $error',
          isSuccess: false,
        );
      }
    });
  }

  Future<void> _downloadEntry(_RemoteEntry entry) async {
    final localDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar destino local',
      lockParentWindow: true,
    );

    if (localDirectory == null || localDirectory.trim().isEmpty) {
      return;
    }

    await _runProcessingAction('Descargando elemento...', () async {
      try {
        await _withSftp((sftp, client) async {
          final targetPath = _joinLocalPath(localDirectory, entry.name);
          await _downloadRemoteEntry(sftp, entry.fullPath, targetPath);
        });
        _showFeedbackMessage('Descarga completada en local.', isSuccess: true);
      } catch (error) {
        _showFeedbackMessage(
          'No se pudo descargar el elemento: $error',
          isSuccess: false,
        );
      }
    });
  }

  Future<void> _showEntryInfo(_RemoteEntry entry) async {
    await _runProcessingAction('Cargando información...', () async {
      try {
        final latestEntry = await _withSftp((sftp, client) async {
          final attrs = await sftp.stat(entry.fullPath, followLink: false);
          return entry.copyWith(attrs: attrs);
        });

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
                    _InfoRow(label: 'Nombre', value: latestEntry.name),
                    _InfoRow(label: 'Ruta', value: latestEntry.fullPath),
                    _InfoRow(label: 'Tipo', value: latestEntry.typeLabel),
                    _InfoRow(
                      label: 'Permisos',
                      value:
                          '${_formatPermissionString(latestEntry.attrs?.mode)} (${_formatPermissionOctal(latestEntry.attrs?.mode)})',
                    ),
                    _InfoRow(
                      label: 'Usuario propietario',
                      value:
                          _extractOwnerFromLongName(latestEntry.longName) ??
                          (latestEntry.attrs?.userID?.toString() ??
                              'No disponible'),
                    ),
                    _InfoRow(
                      label: 'Grupo propietario',
                      value:
                          _extractGroupFromLongName(latestEntry.longName) ??
                          (latestEntry.attrs?.groupID?.toString() ??
                              'No disponible'),
                    ),
                    _InfoRow(
                      label: 'Tamaño',
                      value: _formatSize(latestEntry.attrs?.size),
                    ),
                    _InfoRow(
                      label: 'Última modificación',
                      value: _formatUnixTime(latestEntry.attrs?.modifyTime),
                    ),
                    _InfoRow(
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
        _showFeedbackMessage(
          'No se pudo obtener la información del elemento: $error',
          isSuccess: false,
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
        await _withSftp((sftp, client) async {
          for (final path in paths) {
            final remotePath = _joinRemotePath(
              _currentDirectory,
              _localBasename(path),
            );
            await _uploadLocalFile(sftp, path, remotePath);
          }
        });
        await _loadDirectory(_currentDirectory);
        _showFeedbackMessage(
          'Archivos subidos correctamente.',
          isSuccess: true,
        );
      } catch (error) {
        _showFeedbackMessage(
          'No se pudieron subir los archivos: $error',
          isSuccess: false,
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
        await _withSftp((sftp, client) async {
          final remoteRoot = _joinRemotePath(
            _currentDirectory,
            _localBasename(localDirectory),
          );
          await _uploadLocalDirectory(sftp, localDirectory, remoteRoot);
        });
        await _loadDirectory(_currentDirectory);
        _showFeedbackMessage('Carpeta subida correctamente.', isSuccess: true);
      } catch (error) {
        _showFeedbackMessage(
          'No se pudo subir la carpeta: $error',
          isSuccess: false,
        );
      }
    });
  }

  Future<void> _deleteRemoteEntryRecursive(
    SftpClient sftp,
    String remotePath,
  ) async {
    final attrs = await sftp.stat(remotePath, followLink: false);

    if (attrs.isDirectory && !attrs.isSymbolicLink) {
      final children = await sftp.listdir(remotePath);
      for (final child in children) {
        if (child.filename == '.' || child.filename == '..') {
          continue;
        }

        await _deleteRemoteEntryRecursive(
          sftp,
          _joinRemotePath(remotePath, child.filename),
        );
      }
      await sftp.rmdir(remotePath);
      return;
    }

    await sftp.remove(remotePath);
  }

  Future<void> _downloadRemoteEntry(
    SftpClient sftp,
    String remotePath,
    String localPath,
  ) async {
    final attrs = await sftp.stat(remotePath, followLink: false);

    if (attrs.isDirectory && !attrs.isSymbolicLink) {
      await _downloadRemoteDirectory(sftp, remotePath, localPath);
      return;
    }

    await Directory(localPath).parent.create(recursive: true);
    final output = File(localPath).openWrite();
    await sftp.download(remotePath, output, closeDestination: true);
  }

  Future<void> _downloadRemoteDirectory(
    SftpClient sftp,
    String remoteDirectory,
    String localDirectory,
  ) async {
    await Directory(localDirectory).create(recursive: true);

    final children = await sftp.listdir(remoteDirectory);
    for (final child in children) {
      if (child.filename == '.' || child.filename == '..') {
        continue;
      }

      final remoteChildPath = _joinRemotePath(remoteDirectory, child.filename);
      final localChildPath = _joinLocalPath(localDirectory, child.filename);
      final childEntry = _RemoteEntry.fromSftpName(
        parentDirectory: remoteDirectory,
        name: child,
      );

      if (childEntry.isDirectory && !childEntry.isSymbolicLink) {
        await _downloadRemoteDirectory(sftp, remoteChildPath, localChildPath);
      } else {
        final output = File(localChildPath).openWrite();
        await sftp.download(remoteChildPath, output, closeDestination: true);
      }
    }
  }

  Future<void> _uploadLocalFile(
    SftpClient sftp,
    String localPath,
    String remotePath,
  ) async {
    final file = await sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );

    try {
      final writer = await file.write(
        File(localPath).openRead().cast<Uint8List>(),
      );
      await writer.done;
    } finally {
      await file.close();
    }
  }

  Future<void> _uploadLocalDirectory(
    SftpClient sftp,
    String localDirectory,
    String remoteDirectory,
  ) async {
    await _ensureRemoteDirectory(sftp, remoteDirectory);

    final directory = Directory(localDirectory);
    await for (final entity in directory.list(recursive: false)) {
      final name = _localBasename(entity.path);
      final remotePath = _joinRemotePath(remoteDirectory, name);

      if (entity is File) {
        await _uploadLocalFile(sftp, entity.path, remotePath);
      } else if (entity is Directory) {
        await _uploadLocalDirectory(sftp, entity.path, remotePath);
      }
    }
  }

  Future<void> _ensureRemoteDirectory(
    SftpClient sftp,
    String remoteDirectory,
  ) async {
    try {
      final attrs = await sftp.stat(remoteDirectory, followLink: false);
      if (!attrs.isDirectory) {
        throw Exception('Ya existe un archivo con el mismo nombre.');
      }
      return;
    } on SftpStatusError {
      await sftp.mkdir(remoteDirectory);
    }
  }

  String? _extractOwnerFromLongName(String longName) {
    final parts = longName.trim().split(RegExp(r'\s+'));
    return parts.length >= 4 ? parts[2] : null;
  }

  String? _extractGroupFromLongName(String longName) {
    final parts = longName.trim().split(RegExp(r'\s+'));
    return parts.length >= 5 ? parts[3] : null;
  }

  String _formatPermissionString(SftpFileMode? mode) {
    if (mode == null) {
      return 'No disponible';
    }

    final typePrefix = switch (mode.type) {
      SftpFileType.directory => 'd',
      SftpFileType.symbolicLink => 'l',
      SftpFileType.blockDevice => 'b',
      SftpFileType.characterDevice => 'c',
      SftpFileType.pipe => 'p',
      SftpFileType.socket => 's',
      _ => '-',
    };

    return '$typePrefix'
        '${mode.userRead ? 'r' : '-'}${mode.userWrite ? 'w' : '-'}${mode.userExecute ? 'x' : '-'}'
        '${mode.groupRead ? 'r' : '-'}${mode.groupWrite ? 'w' : '-'}${mode.groupExecute ? 'x' : '-'}'
        '${mode.otherRead ? 'r' : '-'}${mode.otherWrite ? 'w' : '-'}${mode.otherExecute ? 'x' : '-'}';
  }

  String _formatPermissionOctal(SftpFileMode? mode) {
    if (mode == null) {
      return '---';
    }

    return (mode.value & 0x1FF).toRadixString(8).padLeft(3, '0');
  }

  String _formatSize(int? size) {
    if (size == null) {
      return 'No disponible';
    }

    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatUnixTime(int? unixSeconds) {
    if (unixSeconds == null) {
      return 'No disponible';
    }

    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
      isUtc: true,
    ).toLocal();

    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '${dateTime.year}-$month-$day $hour:$minute';
  }

  Widget _buildLeftPanelButton(({String label, IconData icon}) section) {
    final isSelected = _selectedSection == section.label;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _selectedSection = section.label;
          });
        },
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          side: BorderSide(
            color: isSelected ? Colors.deepPurpleAccent : Colors.white24,
          ),
          backgroundColor: isSelected
              ? Colors.deepPurple.withValues(alpha: 0.18)
              : null,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(section.icon, color: Colors.deepPurpleAccent),
        label: Text(section.label),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando contenido remoto...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _loadDirectory(_currentDirectory),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 48, color: Colors.white30),
            SizedBox(height: 12),
            Text(
              'Este directorio está vacío.',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : entry.isSymbolicLink
                ? Icons.link
                : Icons.insert_drive_file_outlined,
            color: entry.isDirectory
                ? Colors.amberAccent
                : entry.isSymbolicLink
                ? Colors.tealAccent
                : Colors.blueGrey.shade100,
          ),
          title: Text(entry.name),
          subtitle: Text(entry.typeLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.isDirectory)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.chevron_right),
                ),
              PopupMenuButton<_EntryAction>(
                tooltip: 'Acciones',
                onSelected: (action) => _handleEntryAction(action, entry),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _EntryAction.rename,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('Cambiar nombre'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EntryAction.download,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.download_outlined),
                      title: Text('Descargar en local'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EntryAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Borrar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EntryAction.info,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline),
                      title: Text('Información y permisos'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: entry.isDirectory ? () => _openChildDirectory(entry) : null,
        );
      },
    );
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
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.dashboard_customize_outlined,
                                  color: Colors.deepPurpleAccent,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Explorador',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            ..._sections.map(
                              (section) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildLeftPanelButton(section),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.folder_open,
                                  size: 28,
                                  color: Colors.deepPurpleAccent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Directorio actual',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _currentDirectory,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _showUploadOptions,
                                  tooltip: 'Subir al servidor',
                                  icon: const Icon(Icons.add),
                                ),
                                if (!_isRootDirectory)
                                  IconButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _openParentDirectory,
                                    tooltip: 'Subir un nivel',
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                IconButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => _loadDirectory(_currentDirectory),
                                  tooltip: 'Recargar',
                                  icon: const Icon(Icons.refresh),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Expanded(child: _buildContent()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _processingLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RemoteEntry {
  const _RemoteEntry({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
    required this.isSymbolicLink,
    required this.longName,
    this.attrs,
  });

  factory _RemoteEntry.fromSftpName({
    required String parentDirectory,
    required SftpName name,
  }) {
    return _RemoteEntry(
      name: name.filename,
      fullPath: parentDirectory == '/'
          ? '/${name.filename}'
          : '$parentDirectory/${name.filename}',
      isDirectory: name.attr.isDirectory,
      isSymbolicLink: name.attr.isSymbolicLink,
      longName: name.longname,
      attrs: name.attr,
    );
  }

  final String name;
  final String fullPath;
  final bool isDirectory;
  final bool isSymbolicLink;
  final String longName;
  final SftpFileAttrs? attrs;

  String get typeLabel {
    if (isDirectory) {
      return 'Carpeta';
    }
    if (isSymbolicLink) {
      return 'Enlace simbólico';
    }
    return 'Archivo';
  }

  _RemoteEntry copyWith({SftpFileAttrs? attrs}) {
    return _RemoteEntry(
      name: name,
      fullPath: fullPath,
      isDirectory: isDirectory,
      isSymbolicLink: isSymbolicLink,
      longName: longName,
      attrs: attrs ?? this.attrs,
    );
  }
}

enum _EntryAction { rename, download, delete, info }

enum _UploadAction { files, directory }

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}
