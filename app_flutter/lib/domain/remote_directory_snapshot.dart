import 'remote_entry.dart';

class RemoteDirectorySnapshot {
  const RemoteDirectorySnapshot({
    required this.directory,
    required this.entries,
  });

  final String directory;
  final List<RemoteEntry> entries;
}
