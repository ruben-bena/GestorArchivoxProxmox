import 'package:flutter/material.dart';

import '../../../domain/remote_entry.dart';
import 'remote_entries_content.dart';

class VisualizerSectionPanel extends StatelessWidget {
  const VisualizerSectionPanel({
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

  static const List<Color> _directoryPalette = [
    Colors.amberAccent,
    Colors.amber,
    Colors.orangeAccent,
    Colors.yellowAccent,
    Colors.deepOrangeAccent,
    Colors.limeAccent,
  ];

  static const List<Color> _filePalette = [
    Colors.deepPurpleAccent,
    Colors.purpleAccent,
    Colors.indigoAccent,
    Colors.blueAccent,
    Colors.tealAccent,
    Colors.cyanAccent,
  ];

  List<_VisualizerSlice> get _slices {
    final sourceEntries = entries
        .where((entry) => !entry.isSymbolicLink)
        .toList();
    if (sourceEntries.isEmpty) {
      return const [];
    }

    final orderedEntries = sourceEntries.toList()
      ..sort((a, b) => ((b.size ?? 0)).compareTo(a.size ?? 0));

    return orderedEntries.asMap().entries.map((item) {
      final index = item.key;
      final entry = item.value;
      final palette = entry.isDirectory ? _directoryPalette : _filePalette;

      return _VisualizerSlice(
        entry: entry,
        color: palette[index % palette.length],
        weight: (entry.size ?? 0) > 0 ? entry.size!.toDouble() : 1,
      );
    }).toList();
  }

  String _formatBytes(int bytes, {String zeroLabel = 'No disponible'}) {
    if (bytes <= 0) {
      return zeroLabel;
    }

    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatEntrySize(RemoteEntry entry) {
    return _formatBytes(entry.size ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final slices = _slices;
    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + ((entry.size ?? 0) > 0 ? entry.size! : 0),
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.remove_red_eye_outlined,
                  size: 28,
                  color: Colors.deepPurpleAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Visualizador del directorio',
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
            if (!isLoading && errorMessage == null && entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  height: 250,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                painter: _DirectoryBaobabPainter(
                                  slices: slices,
                                ),
                                size: Size.infinite,
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatBytes(totalBytes, zeroLabel: '0 B'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 2,
                        child: _VisualizationLegend(
                          slices: slices,
                          formatEntrySize: _formatEntrySize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

class _VisualizationLegend extends StatelessWidget {
  const _VisualizationLegend({
    required this.slices,
    required this.formatEntrySize,
  });

  final List<_VisualizerSlice> slices;
  final String Function(RemoteEntry entry) formatEntrySize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Distribución',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: slices.length,
            itemBuilder: (context, index) {
              final slice = slices[index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: slice.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        slice.entry.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatEntrySize(slice.entry),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DirectoryBaobabPainter extends CustomPainter {
  const _DirectoryBaobabPainter({required this.slices});

  final List<_VisualizerSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final ringWidth = radius * 0.42;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..color = Colors.white10;

    canvas.drawCircle(center, radius - (ringWidth / 2), backgroundPaint);

    if (slices.isEmpty) {
      return;
    }

    final total = slices.fold<double>(0, (sum, slice) => sum + slice.weight);
    var startAngle = -1.57079632679;

    for (final slice in slices) {
      final sweep = (slice.weight / total) * 6.28318530718;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.butt
        ..color = slice.color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - (ringWidth / 2)),
        startAngle,
        sweep,
        false,
        paint,
      );

      startAngle += sweep;
    }

    final centerPaint = Paint()..color = const Color(0xFF1F1F1F);
    canvas.drawCircle(center, radius * 0.38, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _DirectoryBaobabPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _VisualizerSlice {
  const _VisualizerSlice({
    required this.entry,
    required this.color,
    required this.weight,
  });

  final RemoteEntry entry;
  final Color color;
  final double weight;
}
