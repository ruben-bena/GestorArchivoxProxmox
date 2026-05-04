/// Metadatos de una sesión de túnel SSH abierta para un servidor remoto.
class PortForwardSession {
  const PortForwardSession({
    required this.serverPath,
    required this.localPort,
    required this.remotePort,
    required this.startedAt,
  });

  /// Ruta absoluta del proyecto remoto al que pertenece este túnel.
  final String serverPath;
  /// Puerto expuesto en localhost por el túnel SSH.
  final int localPort;
  /// Puerto del servicio remoto que se redirige.
  final int remotePort;
  /// Instante de creación de la sesión para trazabilidad en UI/diagnóstico.
  final DateTime startedAt;
}
