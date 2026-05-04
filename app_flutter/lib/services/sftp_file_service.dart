import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/remote_directory_snapshot.dart';
import '../domain/remote_entry.dart';

/// Servicio SFTP para navegación, transferencia y operaciones de archivos remotos.
class SftpFileService {
  const SftpFileService({
    required this.host,
    required this.username,
    required this.port,
    required this.keyPath,
  });

  final String host;
  final String username;
  final int port;
  final String keyPath;

  /// Carga un directorio remoto y devuelve sus entradas ordenadas para UI.
  Future<RemoteDirectorySnapshot> loadDirectory(String directory) async {
    return _withSftp((sftp, client) async {
      final resolvedDirectory = await sftp.absolute(directory);
      final names = await sftp.listdir(resolvedDirectory);

      final entries =
          names
              .where((name) => name.filename != '.' && name.filename != '..')
              .map(
                (name) => _toRemoteEntry(
                  parentDirectory: resolvedDirectory,
                  name: name,
                ),
              )
              .toList()
            ..sort((a, b) {
              // Primero carpetas y después archivos para navegación más natural.
              if (a.isDirectory != b.isDirectory) {
                return a.isDirectory ? -1 : 1;
              }

              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

      return RemoteDirectorySnapshot(
        directory: resolvedDirectory,
        entries: entries,
      );
    });
  }

  /// Renombra un archivo/carpeta dentro del directorio actual.
  Future<void> rename({
    required String currentDirectory,
    required RemoteEntry entry,
    required String newName,
  }) async {
    final newPath = _joinRemotePath(currentDirectory, newName);
    await _withSftp((sftp, client) => sftp.rename(entry.fullPath, newPath));
  }

  /// Borra una entrada remota (recursivo si es carpeta).
  Future<void> deleteEntry(RemoteEntry entry) async {
    await _withSftp((sftp, client) async {
      await _deleteRemoteEntryRecursive(sftp, entry.fullPath);
    });
  }

  /// Descarga una entrada remota a un directorio local.
  Future<void> downloadEntry({
    required RemoteEntry entry,
    required String localDirectory,
  }) async {
    await _withSftp((sftp, client) async {
      final targetPath = _joinLocalPath(localDirectory, entry.name);
      await _downloadRemoteEntry(sftp, entry.fullPath, targetPath);
    });
  }

  /// Sube múltiples archivos locales al directorio remoto actual.
  Future<void> uploadFiles({
    required String currentDirectory,
    required List<String> localPaths,
  }) async {
    await _withSftp((sftp, client) async {
      for (final path in localPaths) {
        // Conserva el nombre original del archivo dentro del directorio remoto destino.
        final remotePath = _joinRemotePath(
          currentDirectory,
          _localBasename(path),
        );
        await _uploadLocalFile(sftp, path, remotePath);
      }
    });
  }

  /// Sube una carpeta local completa preservando su estructura.
  Future<void> uploadDirectory({
    required String currentDirectory,
    required String localDirectory,
  }) async {
    await _withSftp((sftp, client) async {
      final remoteRoot = _joinRemotePath(
        currentDirectory,
        _localBasename(localDirectory),
      );
      await _uploadLocalDirectory(sftp, localDirectory, remoteRoot);
    });
  }

  /// Reconsulta metadatos de una entrada remota para mostrar detalles actualizados.
  Future<RemoteEntry> getEntryInfo(RemoteEntry entry) async {
    return _withSftp((sftp, client) async {
      final attrs = await sftp.stat(entry.fullPath, followLink: false);
      return entry.copyWith(
        modeValue: attrs.mode?.value,
        userId: attrs.userID,
        groupId: attrs.groupID,
        size: attrs.size,
        modifyTime: attrs.modifyTime,
      );
    });
  }

  /// Descomprime un archivo `.zip` en el servidor remoto.
  Future<void> extractZipEntry(RemoteEntry entry) async {
    // Validación de seguridad: solo archivos ZIP regulares son extraíbles.
    if (entry.isDirectory || !entry.name.toLowerCase().endsWith('.zip')) {
      throw Exception('Solo se pueden descomprimir archivos .zip.');
    }

    await _withSftp((sftp, client) async {
      final parentDirectory = _remoteDirname(entry.fullPath);
      final escapedDirectory = _escapeForSingleQuotes(parentDirectory);
      final escapedFilename = _escapeForSingleQuotes(entry.name);
      final script = '''
if ! command -v unzip >/dev/null 2>&1; then
  echo 'El comando unzip no está disponible en el servidor remoto.' >&2
  exit 1
fi
cd '$escapedDirectory' || exit 1
unzip -o '$escapedFilename'
''';

      final escapedScript = _escapeForSingleQuotes(script);
      await client.run("sh -lc '$escapedScript'");
    });
  }

  /// Crea un cliente SSH autenticado con clave privada.
  Future<SSHClient> _createSshClient() async {
    final privateKey = await File(keyPath).readAsString();
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );

    return SSHClient(
      socket,
      username: username,
      identities: SSHKeyPair.fromPem(privateKey),
    );
  }

  /// Ejecuta una acción con cliente SFTP garantizando cierre de recursos.
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

  /// Convierte un `SftpName` al modelo de dominio usado por la UI.
  RemoteEntry _toRemoteEntry({
    required String parentDirectory,
    required SftpName name,
  }) {
    return RemoteEntry(
      name: name.filename,
      fullPath: parentDirectory == '/'
          ? '/${name.filename}'
          : '$parentDirectory/${name.filename}',
      isDirectory: name.attr.isDirectory,
      isSymbolicLink: name.attr.isSymbolicLink,
      longName: name.longname,
      modeValue: name.attr.mode?.value,
      userId: name.attr.userID,
      groupId: name.attr.groupID,
      size: name.attr.size,
      modifyTime: name.attr.modifyTime,
    );
  }

  /// Une segmentos de ruta remota con semántica POSIX.
  String _joinRemotePath(String parent, String child) {
    if (parent == '/') {
      return '/$child';
    }

    return '$parent/$child';
  }

  /// Une segmentos de ruta local respetando el separador de la plataforma.
  String _joinLocalPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }

    return '$parent${Platform.pathSeparator}$child';
  }

  /// Obtiene el nombre base de una ruta local.
  String _localBasename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  /// Obtiene el directorio padre remoto de una ruta.
  String _remoteDirname(String path) {
    if (path == '/') {
      return '/';
    }

    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final slashIndex = trimmed.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '/';
    }

    return trimmed.substring(0, slashIndex);
  }

  /// Escapa comillas simples para interpolar texto en scripts shell de una línea.
  String _escapeForSingleQuotes(String value) {
    return value.replaceAll("'", "'\"'\"'");
  }

  /// Borra recursivamente archivos/carpetas remotas evitando seguir enlaces simbólicos.
  Future<void> _deleteRemoteEntryRecursive(
    SftpClient sftp,
    String remotePath,
  ) async {
    final attrs = await sftp.stat(remotePath, followLink: false);

    if (attrs.isDirectory && !attrs.isSymbolicLink) {
      // DFS recursivo: elimina hijos antes de remover la carpeta contenedora.
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

  /// Descarga una entrada remota; delega en recursión si se trata de carpeta.
  Future<void> _downloadRemoteEntry(
    SftpClient sftp,
    String remotePath,
    String localPath,
  ) async {
    final attrs = await sftp.stat(remotePath, followLink: false);

    // Las carpetas delegan en descarga recursiva para preservar jerarquía.
    if (attrs.isDirectory && !attrs.isSymbolicLink) {
      await _downloadRemoteDirectory(sftp, remotePath, localPath);
      return;
    }

    await Directory(localPath).parent.create(recursive: true);
    final output = File(localPath).openWrite();
    await sftp.download(remotePath, output, closeDestination: true);
  }

  /// Descarga el contenido completo de un directorio remoto.
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
      final childIsDirectory =
          child.attr.isDirectory && !child.attr.isSymbolicLink;

      if (childIsDirectory) {
        await _downloadRemoteDirectory(sftp, remoteChildPath, localChildPath);
      } else {
        // Descarga de archivo simple en la misma rama local del árbol.
        final output = File(localChildPath).openWrite();
        await sftp.download(remoteChildPath, output, closeDestination: true);
      }
    }
  }

  /// Sube un archivo local a una ruta remota concreta.
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

  /// Recorre y sube una carpeta local completa de forma recursiva.
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
        // Repite recursivamente para replicar la estructura de carpetas en remoto.
        await _uploadLocalDirectory(sftp, entity.path, remotePath);
      }
    }
  }

  /// Crea un directorio remoto si no existe y valida colisiones de nombre.
  Future<void> _ensureRemoteDirectory(
    SftpClient sftp,
    String remoteDirectory,
  ) async {
    try {
      final attrs = await sftp.stat(remoteDirectory, followLink: false);
      if (!attrs.isDirectory) {
        // Evita sobreescribir archivos existentes cuando se esperaba carpeta.
        throw Exception('Ya existe un archivo con el mismo nombre.');
      }
      return;
    } on SftpStatusError {
      // Si no existe, se crea de forma idempotente para continuar la carga.
      await sftp.mkdir(remoteDirectory);
    }
  }
}
