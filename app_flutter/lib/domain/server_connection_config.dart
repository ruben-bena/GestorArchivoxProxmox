/// Configuración persistida de conexión SSH para reutilizarla en el formulario.
class ServerConnectionConfig {
  const ServerConnectionConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.keyPath,
  });

  final String name;
  final String host;
  final String port;
  final String keyPath;

  /// Reconstruye la configuración desde JSON tolerando valores nulos.
  factory ServerConnectionConfig.fromJson(Map<String, dynamic> json) {
    return ServerConnectionConfig(
      name: json['name']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      port: json['port']?.toString() ?? '',
      keyPath: json['keyPath']?.toString() ?? '',
    );
  }

  /// Serializa la configuración al formato que se guarda en disco.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'keyPath': keyPath,
    };
  }

  /// Compara si dos configuraciones representan exactamente la misma entrada.
  bool sameIdentityAs(ServerConnectionConfig other) {
    return name == other.name &&
        host == other.host &&
        port == other.port &&
        keyPath == other.keyPath;
  }
}
