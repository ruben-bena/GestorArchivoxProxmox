import 'remote_entry.dart';

/// Instantánea inmutable del contenido de un directorio remoto.
class RemoteDirectorySnapshot {
  const RemoteDirectorySnapshot({
    required this.directory,
    required this.entries,
  });

  final String directory;
  final List<RemoteEntry> entries;
}
