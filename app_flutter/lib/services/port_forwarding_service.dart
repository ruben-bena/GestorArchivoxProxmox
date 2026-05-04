import 'dart:convert';
import 'dart:io';

import '../domain/port_forward_session.dart';

/// Administra procesos SSH locales que exponen puertos remotos en localhost.
class PortForwardingService {
  final Map<String, ({Process process, PortForwardSession session})> _sessions =
      <String, ({Process process, PortForwardSession session})>{};

  /// Vista de solo lectura de sesiones activas por ruta de servidor remoto.
  Map<String, PortForwardSession> get sessionsByServerPath {
    _cleanupDeadSessionsSync();
    return Map.unmodifiable(
      _sessions.map((key, value) => MapEntry(key, value.session)),
    );
  }

  /// Sincroniza sesiones eliminando túneles que ya no estén vivos.
  Future<void> syncSessions() async {
    final serverPaths = _sessions.keys.toList(growable: false);
    for (final serverPath in serverPaths) {
      final activeSession = _sessions[serverPath];
      if (activeSession == null) {
        continue;
      }

      // Si el proceso ya finalizó, la sesión se considera obsoleta y se purga.
      final exitCode = await _tryGetExitCode(activeSession.process);
      if (exitCode != null) {
        _sessions.remove(serverPath);
      }
    }
  }

  /// Inicia (o reinicia) un túnel SSH para un servidor remoto específico.
  Future<PortForwardSession> startPortForward({
    required String serverPath,
    required String host,
    required String username,
    required int sshPort,
    required String keyPath,
    required int remotePort,
    required int localPort,
  }) async {
    // Limpia estado anterior y evita duplicar túneles para el mismo servidor.
    await syncSessions();
    await stopPortForward(serverPath);

    // Reserva exclusiva de puerto local entre sesiones activas de la app.
    if (_sessions.values.any((item) => item.session.localPort == localPort)) {
      throw Exception(
        'El puerto local $localPort ya está en uso por otra redirección activa.',
      );
    }

    await _ensureLocalPortAvailable(localPort);

    final stderrBuffer = StringBuffer();
    final stdoutBuffer = StringBuffer();
    final process = await Process.start('ssh', [
      '-N',
      '-L',
      '$localPort:127.0.0.1:$remotePort',
      '-i',
      keyPath,
      '-p',
      '$sshPort',
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=8',
      '-o',
      'ExitOnForwardFailure=yes',
      '-o',
      'StrictHostKeyChecking=no',
      '-o',
      'UserKnownHostsFile=/dev/null',
      '-o',
      'ServerAliveInterval=30',
      '$username@$host',
    ]);

    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
    process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);

    const bootTimeout = Duration(seconds: 4);
    // Si no sale en la ventana de arranque, se considera "vivo" y operativo.
    final exitCode = await Future.any<int>([
      process.exitCode,
      Future<int>.delayed(bootTimeout, () => -1),
    ]);

    // Salida temprana: propaga stderr/stdout como mensaje de error accionable.
    if (exitCode != -1) {
      final stderrText = stderrBuffer.toString().trim();
      final stdoutText = stdoutBuffer.toString().trim();
      final output = stderrText.isNotEmpty ? stderrText : stdoutText;
      throw Exception(
        output.isEmpty
            ? 'El túnel SSH no pudo iniciarse (código $exitCode).'
            : output,
      );
    }

    final session = PortForwardSession(
      serverPath: serverPath,
      localPort: localPort,
      remotePort: remotePort,
      startedAt: DateTime.now(),
    );

    _sessions[serverPath] = (process: process, session: session);
    // Limpieza reactiva cuando el proceso termina por cualquier motivo.
    process.exitCode.then((_) {
      final active = _sessions[serverPath];
      if (active != null && identical(active.process, process)) {
        _sessions.remove(serverPath);
      }
    });

    return session;
  }

  /// Cierra de forma segura el túnel asociado al servidor indicado.
  Future<void> stopPortForward(String serverPath) async {
    await syncSessions();
    final activeSession = _sessions.remove(serverPath);
    if (activeSession == null) {
      return;
    }

    // Primer intento de cierre elegante para que SSH libere recursos correctamente.
    activeSession.process.kill(ProcessSignal.sigterm);

    try {
      await activeSession.process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Fallback forzado si el proceso no responde a SIGTERM.
      activeSession.process.kill(ProcessSignal.sigkill);
      try {
        await activeSession.process.exitCode.timeout(
          const Duration(seconds: 1),
        );
      } catch (_) {
        // Ignorado: el proceso ya debería haber sido terminado.
      }
    }
  }

  /// Libera todos los túneles activos.
  Future<void> dispose() async {
    await syncSessions();
    final serverPaths = _sessions.keys.toList(growable: false);
    for (final serverPath in serverPaths) {
      await stopPortForward(serverPath);
    }
  }

  /// Limpieza rápida no bloqueante de sesiones muertas.
  void _cleanupDeadSessionsSync() {
    final serverPaths = _sessions.keys.toList(growable: false);
    for (final serverPath in serverPaths) {
      final activeSession = _sessions[serverPath];
      if (activeSession == null) {
        continue;
      }

      // No bloquea el hilo: agenda limpieza cuando el proceso informe su salida.
      activeSession.process.exitCode.then((_) {
        final current = _sessions[serverPath];
        if (current != null && identical(current.process, activeSession.process)) {
          _sessions.remove(serverPath);
        }
      });
    }
  }

  /// Devuelve el código de salida si el proceso terminó; `null` si sigue vivo.
  Future<int?> _tryGetExitCode(Process process) async {
    final exitCode = await Future.any<int>([
      process.exitCode,
      Future<int>.delayed(Duration.zero, () => -1),
    ]);

    return exitCode == -1 ? null : exitCode;
  }

  /// Valida que un puerto local esté libre antes de abrir el túnel.
  Future<void> _ensureLocalPortAvailable(int localPort) async {
    if (localPort < 1 || localPort > 65535) {
      throw Exception('Puerto local inválido: $localPort.');
    }

    ServerSocket? probe;
    try {
      probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    } on SocketException {
      throw Exception(
        'El puerto local $localPort ya está ocupado por otro proceso.',
      );
    } finally {
      await probe?.close();
    }
  }
}
