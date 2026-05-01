import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/remote_directory_snapshot.dart';
import '../domain/remote_entry.dart';

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

  Future<void> rename({
    required String currentDirectory,
    required RemoteEntry entry,
    required String newName,
  }) async {
    final newPath = _joinRemotePath(currentDirectory, newName);
    await _withSftp((sftp, client) => sftp.rename(entry.fullPath, newPath));
  }

  Future<void> deleteEntry(RemoteEntry entry) async {
    await _withSftp((sftp, client) async {
      await _deleteRemoteEntryRecursive(sftp, entry.fullPath);
    });
  }

  Future<void> downloadEntry({
    required RemoteEntry entry,
    required String localDirectory,
  }) async {
    await _withSftp((sftp, client) async {
      final targetPath = _joinLocalPath(localDirectory, entry.name);
      await _downloadRemoteEntry(sftp, entry.fullPath, targetPath);
    });
  }

  Future<void> uploadFiles({
    required String currentDirectory,
    required List<String> localPaths,
  }) async {
    await _withSftp((sftp, client) async {
      for (final path in localPaths) {
        final remotePath = _joinRemotePath(currentDirectory, _localBasename(path));
        await _uploadLocalFile(sftp, path, remotePath);
      }
    });
  }

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
      final childIsDirectory =
          child.attr.isDirectory && !child.attr.isSymbolicLink;

      if (childIsDirectory) {
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
}
