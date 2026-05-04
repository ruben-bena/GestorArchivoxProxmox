import 'package:flutter/material.dart';

import '../../../domain/remote_entry.dart';
import 'remote_entries_content.dart';

/// Panel que combina listado de entradas y visualización proporcional por tamaño.
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

  /// Paleta para sectores que representan carpetas.
  static const List<Color> _directoryPalette = [
    Colors.amberAccent,
    Colors.amber,
    Colors.orangeAccent,
    Colors.yellowAccent,
    Colors.deepOrangeAccent,
    Colors.limeAccent,
  ];

  /// Paleta para sectores que representan archivos.
  static const List<Color> _filePalette = [
    Colors.deepPurpleAccent,
    Colors.purpleAccent,
    Colors.indigoAccent,
    Colors.blueAccent,
    Colors.tealAccent,
    Colors.cyanAccent,
  ];

  /// Convierte las entradas en porciones ponderadas para la visualización circular.
  List<_VisualizerSlice> get _slices {
    // Los enlaces simbólicos se excluyen para no duplicar tamaños ni rutas derivadas.
    final sourceEntries = entries
        .where((entry) => !entry.isSymbolicLink)
        .toList();
    if (sourceEntries.isEmpty) {
      return const [];
    }

    // Orden descendente para que los elementos grandes queden primero en la leyenda.
    final orderedEntries = sourceEntries.toList()
      ..sort((a, b) => ((b.size ?? 0)).compareTo(a.size ?? 0));

    return orderedEntries.asMap().entries.map((item) {
      final index = item.key;
      final entry = item.value;
      final palette = entry.isDirectory ? _directoryPalette : _filePalette;

      return _VisualizerSlice(
        entry: entry,
        // La paleta rota por índice para mantener colores estables aunque haya muchos elementos.
        color: palette[index % palette.length],
        // Se fuerza peso mínimo 1 para evitar sectores de ángulo cero en elementos sin tamaño.
        weight: (entry.size ?? 0) > 0 ? entry.size!.toDouble() : 1,
      );
    }).toList();
  }

  /// Formatea bytes en unidades legibles.
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

  /// Formato de tamaño para la leyenda.
  String _formatEntrySize(RemoteEntry entry) {
    return _formatBytes(entry.size ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final slices = _slices;
    // El total ignora tamaños nulos/no positivos para reflejar bytes reales.
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
            // El gráfico solo se muestra cuando hay datos válidos y ningún estado transitorio.
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
              // Se reutiliza el listado estándar para acciones y navegación de entradas.
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

/// Leyenda lateral con color, nombre y tamaño de cada porción.
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

/// Painter que dibuja un anillo proporcional al peso de cada entrada.
class _DirectoryBaobabPainter extends CustomPainter {
  const _DirectoryBaobabPainter({required this.slices});

  static const double _fullCircleRadians = 6.28318530718;
  static const double _startAtTopRadians = -1.57079632679;

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

    // Sin datos: se conserva solo el anillo base como estado neutro.
    if (slices.isEmpty) {
      return;
    }

    // Normaliza cada peso a una fracción del círculo completo.
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.weight);
    var startAngle = _startAtTopRadians;

    for (final slice in slices) {
      final sweep = (slice.weight / total) * _fullCircleRadians;
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

      // El siguiente segmento comienza justo donde termina el actual.
      startAngle += sweep;
    }

    // Disco central decorativo para mejorar legibilidad del total.
    final centerPaint = Paint()..color = const Color(0xFF1F1F1F);
    canvas.drawCircle(center, radius * 0.38, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _DirectoryBaobabPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

/// Nodo de datos para cada sector del visualizador.
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
