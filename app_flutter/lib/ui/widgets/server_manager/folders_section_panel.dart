import 'package:flutter/material.dart';

import '../../../domain/remote_entry.dart';
import 'remote_entries_content.dart';

/// Panel principal para navegación y acciones sobre el directorio remoto actual.
class FoldersSectionPanel extends StatelessWidget {
  const FoldersSectionPanel({
    super.key,
    required this.currentDirectory,
    required this.isLoading,
    required this.isRootDirectory,
    required this.errorMessage,
    required this.entries,
    required this.onUpload,
    required this.onGoParent,
    required this.onRefresh,
    required this.onRetry,
    required this.onOpenDirectory,
    required this.onActionSelected,
  });

  final String currentDirectory;
  final bool isLoading;
  final bool isRootDirectory;
  final String? errorMessage;
  final List<RemoteEntry> entries;
  final VoidCallback onUpload;
  final VoidCallback onGoParent;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  final ValueChanged<RemoteEntry> onOpenDirectory;
  final void Function(EntryAction action, RemoteEntry entry) onActionSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                        currentDirectory,
                        style: const TextStyle(color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: isLoading ? null : onUpload,
                  tooltip: 'Subir al servidor',
                  icon: const Icon(Icons.add),
                ),
                if (!isRootDirectory)
                  IconButton(
                    onPressed: isLoading ? null : onGoParent,
                    tooltip: 'Subir un nivel',
                    icon: const Icon(Icons.arrow_upward),
                  ),
                IconButton(
                  onPressed: isLoading ? null : onRefresh,
                  tooltip: 'Recargar',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: RemoteEntriesContent(
                isLoading: isLoading,
                errorMessage: errorMessage,
                entries: entries,
                onRetry: onRetry,
                onOpenDirectory: onOpenDirectory,
                onActionSelected: onActionSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
