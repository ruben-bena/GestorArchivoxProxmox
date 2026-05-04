import 'package:flutter/material.dart';

import '../../../domain/managed_remote_server.dart';

/// Panel de gestión de servidores detectados (Java/NodeJS) con acciones operativas.
class ManagedServersSectionPanel extends StatelessWidget {
  const ManagedServersSectionPanel({
    super.key,
    required this.currentDirectory,
    required this.isLoading,
    required this.errorMessage,
    required this.servers,
    required this.discoveryDepth,
    required this.onRefresh,
    required this.onRetry,
    required this.onDiscoveryDepthChanged,
    required this.onStartServer,
    required this.onStopServer,
    required this.onRestartServer,
    required this.onRedirectPort,
    required this.onStopRedirect,
  });

  final String currentDirectory;
  final bool isLoading;
  final String? errorMessage;
  final List<ManagedRemoteServer> servers;
  final int discoveryDepth;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  final ValueChanged<int> onDiscoveryDepthChanged;
  final ValueChanged<ManagedRemoteServer> onStartServer;
  final ValueChanged<ManagedRemoteServer> onStopServer;
  final ValueChanged<ManagedRemoteServer> onRestartServer;
  final ValueChanged<ManagedRemoteServer> onRedirectPort;
  final ValueChanged<ManagedRemoteServer> onStopRedirect;

  @override
  Widget build(BuildContext context) {
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
                  Icons.storage_outlined,
                  size: 28,
                  color: Colors.deepPurpleAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Servidores Java/NodeJS',
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
                  onPressed: isLoading ? null : onRefresh,
                  tooltip: 'Actualizar lista',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Profundidad de búsqueda',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: isLoading || discoveryDepth <= 0
                      ? null
                      // Impide profundidades negativas al decrementar.
                      : () => onDiscoveryDepthChanged(discoveryDepth - 1),
                  tooltip: 'Reducir profundidad',
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Text(
                    '$discoveryDepth',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: isLoading || discoveryDepth >= 10
                      ? null
                      // Limita la exploración para evitar búsquedas excesivas.
                      : () => onDiscoveryDepthChanged(discoveryDepth + 1),
                  tooltip: 'Aumentar profundidad',
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '0 = solo directorio actual',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Prioridad de estados: carga -> error -> vacío -> listado con tarjetas.
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Detectando servidores Java y NodeJS...'),
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

    if (servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_outlined, size: 48, color: Colors.white30),
            const SizedBox(height: 12),
            Text(
              'No se detectaron proyectos Java o NodeJS hasta profundidad $discoveryDepth.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: servers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        // Cada tarjeta concentra el estado y las acciones de un servidor concreto.
        final server = servers[index];

        return _ManagedServerCard(
          server: server,
          onStart: () => onStartServer(server),
          onStop: () => onStopServer(server),
          onRestart: () => onRestartServer(server),
          onRedirect: () => onRedirectPort(server),
          onStopRedirect: () => onStopRedirect(server),
        );
      },
    );
  }
}

/// Tarjeta visual con metadatos del servidor y botones de control remoto.
class _ManagedServerCard extends StatelessWidget {
  const _ManagedServerCard({
    required this.server,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onRedirect,
    required this.onStopRedirect,
  });

  final ManagedRemoteServer server;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onRedirect;
  final VoidCallback onStopRedirect;

  @override
  Widget build(BuildContext context) {
    final accentColor = server.type.accentColor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(server.type.icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Chips de resumen rápido para identificar tipo/estado/puerto.
                        _ChipLabel(
                          label: server.type.label,
                          color: accentColor,
                        ),
                        _ChipLabel(
                          label: server.isRunning
                              ? 'En ejecución'
                              : 'Detenido',
                          color: server.isRunning
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                        _ChipLabel(
                          label: 'Puerto ${server.detectedPort}',
                          color: Colors.blueAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(label: 'Ruta', value: server.fullPath),
          _InfoLine(label: 'Comando detectado', value: server.startCommandLabel),
          _InfoLine(
            label: 'Redirección',
            value: server.hasActivePortForward
                ? 'localhost:${server.forwardedLocalPort} → remoto:${server.forwardedRemotePort}'
                : 'Sin redirección activa',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                // Arranque deshabilitado si el servicio ya está activo.
                onPressed: server.isRunning ? null : onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Arrancar'),
              ),
              OutlinedButton.icon(
                // Parada deshabilitada si no hay proceso detectado en ejecución.
                onPressed: server.isRunning ? onStop : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Parar'),
              ),
              OutlinedButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reiniciar'),
              ),
              OutlinedButton.icon(
                onPressed: onRedirect,
                icon: const Icon(Icons.swap_horiz_outlined),
                label: Text(
                  server.hasActivePortForward
                      ? 'Cambiar redirección'
                      : 'Redirigir puerto',
                ),
              ),
              if (server.hasActivePortForward)
                OutlinedButton.icon(
                  // Solo se muestra cuando existe una redirección a cerrar.
                  onPressed: onStopRedirect,
                  icon: const Icon(Icons.link_off_outlined),
                  label: const Text('Cerrar redirección'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip compacto para resaltar atributos de estado en la tarjeta.
class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Fila de datos clave/valor para metadatos del servidor.
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 126,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
