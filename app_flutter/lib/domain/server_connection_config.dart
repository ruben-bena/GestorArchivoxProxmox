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

  factory ServerConnectionConfig.fromJson(Map<String, dynamic> json) {
    return ServerConnectionConfig(
      name: json['name']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      port: json['port']?.toString() ?? '',
      keyPath: json['keyPath']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'keyPath': keyPath,
    };
  }

  bool sameIdentityAs(ServerConnectionConfig other) {
    return name == other.name &&
        host == other.host &&
        port == other.port &&
        keyPath == other.keyPath;
  }
}
