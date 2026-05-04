import 'remote_entry.dart';

/// Instantánea inmutable del contenido de un directorio remoto.
class RemoteDirectorySnapshot {
  const RemoteDirectorySnapshot({
    required this.directory,
    required this.entries,
  });

  /// Ruta remota ya normalizada/resuelta por el backend SFTP.
  final String directory;
  /// Entradas del directorio en el instante de lectura.
  final List<RemoteEntry> entries;
}
