import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../domain/ssh_target.dart';

/// Encapsula la normalización de destinos SSH y una prueba básica de conexión.
class SshConnectionService {
  const SshConnectionService();

  /// Interpreta host/URI y devuelve un [SshTarget] válido o `null` si es inválido.
  SshTarget? parseTarget(String input) {
    final rawValue = input.trim();
    if (rawValue.isEmpty) {
      return null;
    }

    final value = rawValue.contains('://') ? rawValue : 'ssh://$rawValue';
    final parsedUri = Uri.tryParse(value);
    if (parsedUri == null || parsedUri.host.isEmpty) {
      return null;
    }

    final userFromUri = parsedUri.userInfo.isNotEmpty
        ? parsedUri.userInfo
        : null;
    final fallbackUser =
        Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        'root';

    return SshTarget(
      host: parsedUri.host,
      username: userFromUri ?? fallbackUser,
      port: parsedUri.hasPort ? parsedUri.port : null,
    );
  }

  /// Ejecuta un comando de salud remoto para validar credenciales y conectividad.
  Future<String> runHealthcheck({
    required SshTarget target,
    required String keyPath,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    SSHClient? client;

    try {
      final privateKey = await File(keyPath).readAsString();
      final socket = await SSHSocket.connect(
        target.host,
        target.port!,
        timeout: timeout,
      );

      client = SSHClient(
        socket,
        username: target.username,
        identities: SSHKeyPair.fromPem(privateKey),
      );

      final result = await client.run('ls -la');
      return utf8.decode(result).trim();
    } finally {
      client?.close();
    }
  }
}
