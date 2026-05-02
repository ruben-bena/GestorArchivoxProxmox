import 'package:flutter/material.dart';

import '../../../domain/remote_entry.dart';

/// Acciones disponibles para cada entrada remota en el listado.
enum EntryAction { rename, download, extractZip, delete, info }

/// Estado visual del contenido de un directorio: carga, error, vacío o listado.
class RemoteEntriesContent extends StatelessWidget {
  const RemoteEntriesContent({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.entries,
    required this.onRetry,
    required this.onOpenDirectory,
    required this.onActionSelected,
  });

  final bool isLoading;
  final String? errorMessage;
  final List<RemoteEntry> entries;
  final VoidCallback onRetry;
  final ValueChanged<RemoteEntry> onOpenDirectory;
  final void Function(EntryAction action, RemoteEntry entry) onActionSelected;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
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

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (entries.isEmpty) {
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
      itemCount: entries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isZipFile =
            !entry.isDirectory && entry.name.toLowerCase().endsWith('.zip');

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              PopupMenuButton<EntryAction>(
                tooltip: 'Acciones',
                onSelected: (action) => onActionSelected(action, entry),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: EntryAction.rename,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('Cambiar nombre'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: EntryAction.download,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.download_outlined),
                      title: Text('Descargar en local'),
                    ),
                  ),
                  if (isZipFile)
                    const PopupMenuItem(
                      value: EntryAction.extractZip,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.folder_zip_outlined),
                        title: Text('Descomprimir'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: EntryAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Borrar'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: EntryAction.info,
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
          onTap: entry.isDirectory ? () => onOpenDirectory(entry) : null,
        );
      },
    );
  }
}
