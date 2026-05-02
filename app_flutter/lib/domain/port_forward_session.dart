/// Metadatos de una sesión de túnel SSH abierta para un servidor remoto.
class PortForwardSession {
  const PortForwardSession({
    required this.serverPath,
    required this.localPort,
    required this.remotePort,
    required this.startedAt,
  });

  final String serverPath;
  final int localPort;
  final int remotePort;
  final DateTime startedAt;
}
