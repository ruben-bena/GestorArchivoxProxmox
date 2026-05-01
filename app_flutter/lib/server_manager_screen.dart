import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
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
  static const String _outputSeparator = '__GESTOR_ARCHIVO_SEPARATOR__';
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDirectory(widget.initialDirectory);
  }

  Future<void> _loadDirectory(String directory) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    SSHClient? client;

    try {
      final privateKey = await File(widget.keyPath).readAsString();
      final socket = await SSHSocket.connect(
        widget.host,
        widget.port,
        timeout: const Duration(seconds: 10),
      );

      client = SSHClient(
        socket,
        username: widget.username,
        identities: SSHKeyPair.fromPem(privateKey),
      );

      final command = _buildListCommand(directory);
      final result = await client.run(command);
      final response = utf8.decode(result).trimRight();
      final separatorIndex = response.indexOf(_outputSeparator);

      if (separatorIndex == -1) {
        throw const FormatException(
          'No se pudo interpretar la respuesta del servidor.',
        );
      }

      final resolvedDirectory = response.substring(0, separatorIndex).trim();
      final rawEntries = response
          .substring(separatorIndex + _outputSeparator.length)
          .replaceFirst(RegExp(r'^\r?\n'), '')
          .trimRight();

      final entries =
          rawEntries.isEmpty
                ? <_RemoteEntry>[]
                : rawEntries
                      .split('\n')
                      .where((line) => line.trim().isNotEmpty)
                      .map(_parseEntry)
                      .whereType<_RemoteEntry>()
                      .toList()
            ..sort((a, b) {
              if (a.isDirectory != b.isDirectory) {
                return a.isDirectory ? -1 : 1;
              }

              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

      if (!mounted) {
        return;
      }

      setState(() {
        _currentDirectory = resolvedDirectory;
        _entries = entries;
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
    } finally {
      client?.close();
    }
  }

  String _buildListCommand(String directory) {
    final quotedDirectory = _quoteForShell(directory);

    return "cd $quotedDirectory && pwd && printf '$_outputSeparator\\n' && find . -maxdepth 1 -mindepth 1 -printf '%y\\t%f\\n' | sort -k2";
  }

  String _quoteForShell(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  _RemoteEntry? _parseEntry(String line) {
    final parts = line.split('\t');
    if (parts.length < 2) {
      return null;
    }

    return _RemoteEntry(
      name: parts.sublist(1).join('\t'),
      isDirectory: parts.first == 'd',
    );
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

  void _openChildDirectory(String name) {
    final childPath = _currentDirectory == '/'
        ? '/$name'
        : '$_currentDirectory/$name';
    _loadDirectory(childPath);
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
                : Icons.insert_drive_file_outlined,
            color: entry.isDirectory
                ? Colors.amberAccent
                : Colors.blueGrey.shade100,
          ),
          title: Text(entry.name),
          subtitle: Text(entry.isDirectory ? 'Carpeta' : 'Archivo'),
          trailing: entry.isDirectory ? const Icon(Icons.chevron_right) : null,
          onTap: entry.isDirectory
              ? () => _openChildDirectory(entry.name)
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestor de archivos Proxmox')),
      body: Padding(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  style: const TextStyle(color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
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
    );
  }
}

class _RemoteEntry {
  const _RemoteEntry({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;
}
