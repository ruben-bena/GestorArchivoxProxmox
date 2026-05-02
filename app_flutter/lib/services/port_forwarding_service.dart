import 'dart:convert';
import 'dart:io';

import '../domain/port_forward_session.dart';

class PortForwardingService {
  final Map<String, ({Process process, PortForwardSession session})> _sessions =
      <String, ({Process process, PortForwardSession session})>{};

  Map<String, PortForwardSession> get sessionsByServerPath {
    return Map.unmodifiable(
      _sessions.map((key, value) => MapEntry(key, value.session)),
    );
  }

  Future<PortForwardSession> startPortForward({
    required String serverPath,
    required String host,
    required String username,
    required int sshPort,
    required String keyPath,
    required int remotePort,
    required int localPort,
  }) async {
    await stopPortForward(serverPath);

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
      'ExitOnForwardFailure=yes',
      '-o',
      'StrictHostKeyChecking=no',
      '-o',
      'ServerAliveInterval=30',
      '$username@$host',
    ]);

    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
    process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);

    const bootTimeout = Duration(milliseconds: 900);
    final exitCode = await Future.any<int>([
      process.exitCode,
      Future<int>.delayed(bootTimeout, () => -1),
    ]);

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
    return session;
  }

  Future<void> stopPortForward(String serverPath) async {
    final activeSession = _sessions.remove(serverPath);
    if (activeSession == null) {
      return;
    }

    activeSession.process.kill(ProcessSignal.sigterm);

    try {
      await activeSession.process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
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

  Future<void> dispose() async {
    final serverPaths = _sessions.keys.toList(growable: false);
    for (final serverPath in serverPaths) {
      await stopPortForward(serverPath);
    }
  }
}
