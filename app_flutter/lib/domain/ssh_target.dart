class SshTarget {
  const SshTarget({
    required this.host,
    required this.username,
    this.port,
  });

  final String host;
  final String username;
  final int? port;

  SshTarget copyWith({
    String? host,
    String? username,
    int? port,
    bool clearPort = false,
  }) {
    return SshTarget(
      host: host ?? this.host,
      username: username ?? this.username,
      port: clearPort ? null : (port ?? this.port),
    );
  }
}
