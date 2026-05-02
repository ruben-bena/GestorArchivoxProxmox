import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../domain/managed_remote_server.dart';
import '../domain/remote_entry.dart';

/// Descubre y controla proyectos Java/NodeJS en el servidor remoto vía SSH.
class RemoteServerControlService {
  const RemoteServerControlService({
    required this.host,
    required this.username,
    required this.port,
    required this.keyPath,
  });

  final String host;
  final String username;
  final int port;
  final String keyPath;

  /// Inspecciona directorio actual y subdirectorios inmediatos para detectar servidores.
  Future<List<ManagedRemoteServer>> discoverServers({
    required String currentDirectory,
    required List<RemoteEntry> entries,
  }) async {
    return _withClient((client, sftp) async {
      final servers = <ManagedRemoteServer>[];
      final inspectedPaths = <String>{};
      final candidatePaths = <({String name, String path})>[
        (name: _basename(currentDirectory), path: currentDirectory),
        ...entries
            .where((entry) => entry.isDirectory && !entry.isSymbolicLink)
            .map((entry) => (name: entry.name, path: entry.fullPath)),
      ];

      for (final candidate in candidatePaths) {
        if (!inspectedPaths.add(candidate.path)) {
          continue;
        }

        final markerFiles = await _listDirectoryNames(sftp, candidate.path);
        final serverType = _resolveServerType(markerFiles);
        if (serverType == null) {
          continue;
        }

        final startCommandLabel = _resolveStartCommandLabel(
          serverType: serverType,
          markerFiles: markerFiles,
        );
        final detectedPort = await _detectPreferredPort(
          client: client,
          directory: candidate.path,
          serverType: serverType,
        );
        final isRunning = await _isPortListening(
          client: client,
          port: detectedPort,
        );

        servers.add(
          ManagedRemoteServer(
            name: candidate.name,
            fullPath: candidate.path,
            type: serverType,
            startCommandLabel: startCommandLabel,
            detectedPort: detectedPort,
            isRunning: isRunning,
          ),
        );
      }

      servers.sort((a, b) {
        if (a.isRunning != b.isRunning) {
          return a.isRunning ? -1 : 1;
        }

        if (a.type != b.type) {
          return a.type.label.compareTo(b.type.label);
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return servers;
    });
  }

  /// Arranca un servidor remoto según su tipo y estructura detectada.
  Future<void> startServer(ManagedRemoteServer server) async {
    await _withClient((client, sftp) async {
      await _runCommand(client, _buildStartCommand(server));
    });
  }

  /// Detiene el proceso que escucha en el puerto detectado del servidor.
  Future<void> stopServer(ManagedRemoteServer server) async {
    await _withClient((client, sftp) async {
      final targetPort = server.detectedPort;
      await _runCommand(client, '''
port=$targetPort
pids=""
if command -v lsof >/dev/null 2>&1; then
  pids=\$(lsof -tiTCP:$targetPort -sTCP:LISTEN 2>/dev/null || true)
elif command -v fuser >/dev/null 2>&1; then
  pids=\$(fuser $targetPort/tcp 2>/dev/null || true)
elif command -v ss >/dev/null 2>&1; then
  pids=\$(ss -ltnpH 2>/dev/null | sed -nE "s/.*:$targetPort .*pid=([0-9]+).*/\\1/p" | sort -u)
fi

if [ -n "\$pids" ]; then
  kill \$pids 2>/dev/null || true
  sleep 1
fi
''');
    });
  }

  /// Reinicia el servidor remoto aplicando parada y arranque secuencial.
  Future<void> restartServer(ManagedRemoteServer server) async {
    await stopServer(server);
    await Future<void>.delayed(const Duration(seconds: 1));
    await startServer(server);
  }

  /// Ejecuta una acción con cliente SSH+SFTP garantizando liberación de recursos.
  Future<T> _withClient<T>(
    Future<T> Function(SSHClient client, SftpClient sftp) action,
  ) async {
    final privateKey = await File(keyPath).readAsString();
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );

    final client = SSHClient(
      socket,
      username: username,
      identities: SSHKeyPair.fromPem(privateKey),
    );

    try {
      final sftp = await client.sftp();
      try {
        return await action(client, sftp);
      } finally {
        sftp.close();
      }
    } finally {
      client.close();
    }
  }

  /// Lista nombres de entradas de un directorio remoto.
  Future<Set<String>> _listDirectoryNames(
    SftpClient sftp,
    String directory,
  ) async {
    final names = await sftp.listdir(directory);
    return names.map((item) => item.filename).toSet();
  }

  /// Resuelve tipo de servidor a partir de archivos marcadores.
  ManagedServerType? _resolveServerType(Set<String> markerFiles) {
    if (markerFiles.contains('package.json')) {
      return ManagedServerType.nodeJs;
    }

    if (markerFiles.contains('pom.xml') ||
        markerFiles.contains('build.gradle') ||
        markerFiles.contains('build.gradle.kts')) {
      return ManagedServerType.java;
    }

    return null;
  }

  /// Define el comando de arranque sugerido para mostrar en UI.
  String _resolveStartCommandLabel({
    required ManagedServerType serverType,
    required Set<String> markerFiles,
  }) {
    switch (serverType) {
      case ManagedServerType.nodeJs:
        return 'npm run dev';
      case ManagedServerType.java:
        if (markerFiles.contains('mvnw') || markerFiles.contains('pom.xml')) {
          return markerFiles.contains('mvnw')
              ? './mvnw spring-boot:run'
              : 'mvn spring-boot:run';
        }
        return markerFiles.contains('gradlew')
            ? './gradlew bootRun'
            : 'gradle bootRun';
    }
  }

  /// Detecta el puerto preferido leyendo configuración típica por stack.
  Future<int> _detectPreferredPort({
    required SSHClient client,
    required String directory,
    required ManagedServerType serverType,
  }) async {
    final escapedDirectory = _escapeForSingleQuotes(directory);
    final script = switch (serverType) {
      ManagedServerType.nodeJs =>
        '''
dir='$escapedDirectory'
port=\$(grep -Eo '(--port[ =]|PORT=)[0-9]{2,5}' "\$dir/package.json" 2>/dev/null | grep -Eo '[0-9]{2,5}' | head -n1)
if [ -z "\$port" ]; then
  if grep -qi 'vite' "\$dir/package.json" 2>/dev/null; then
    port=5173
  elif grep -qi 'next' "\$dir/package.json" 2>/dev/null; then
    port=3000
  else
    port=3000
  fi
fi
printf '%s' "\$port"
''',
      ManagedServerType.java =>
        '''
dir='$escapedDirectory'
port=\$(find "\$dir" -maxdepth 4 -type f \\( -name 'application.properties' -o -name 'application.yml' -o -name 'application.yaml' \\) 2>/dev/null | while read -r file; do
  result=\$(grep -E '^[[:space:]]*server\\.port[[:space:]]*[:=][[:space:]]*[0-9]{2,5}' "\$file" 2>/dev/null | head -n1 | sed -E 's/.*[:=][[:space:]]*([0-9]{2,5}).*/\\1/')
  if [ -n "\$result" ]; then
    printf '%s' "\$result"
    break
  fi
done)
if [ -z "\$port" ]; then
  port=8080
fi
printf '%s' "\$port"
''',
    };

    final output = await _runCommand(client, script);
    return int.tryParse(output.trim()) ?? serverType.defaultPort;
  }

  /// Comprueba si el puerto remoto está escuchando actualmente.
  Future<bool> _isPortListening({
    required SSHClient client,
    required int port,
  }) async {
    final output = await _runCommand(client, '''
port=$port
if command -v ss >/dev/null 2>&1; then
  ss -tlnH 2>/dev/null | awk '{print \$4}' | grep -E "(^|:)\$port\$" >/dev/null && printf 'running' || printf 'stopped'
elif command -v netstat >/dev/null 2>&1; then
  netstat -tln 2>/dev/null | awk '{print \$4}' | grep -E "(^|:)\$port\$" >/dev/null && printf 'running' || printf 'stopped'
else
  printf 'stopped'
fi
''');
    return output.trim() == 'running';
  }

  /// Construye el script de arranque remoto según tipo de servidor.
  String _buildStartCommand(ManagedRemoteServer server) {
    final escapedDirectory = _escapeForSingleQuotes(server.fullPath);
    final escapedLogName = _escapeForSingleQuotes(
      '.gestor_${server.type.name}_${server.detectedPort}.log',
    );

    return switch (server.type) {
      ManagedServerType.nodeJs =>
        '''
dir='$escapedDirectory'
cd "\$dir" || exit 1
if [ -f package.json ] && grep -q '"dev"[[:space:]]*:' package.json 2>/dev/null; then
  nohup npm run dev > "$escapedLogName" 2>&1 &
elif [ -f package.json ] && grep -q '"start"[[:space:]]*:' package.json 2>/dev/null; then
  nohup npm start > "$escapedLogName" 2>&1 &
else
  echo 'No se encontró un script dev/start en package.json.' >&2
  exit 1
fi
''',
      ManagedServerType.java =>
        '''
dir='$escapedDirectory'
cd "\$dir" || exit 1
if [ -x ./mvnw ]; then
  nohup ./mvnw spring-boot:run > "$escapedLogName" 2>&1 &
elif [ -f pom.xml ]; then
  nohup mvn spring-boot:run > "$escapedLogName" 2>&1 &
elif [ -x ./gradlew ]; then
  nohup ./gradlew bootRun > "$escapedLogName" 2>&1 &
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  nohup gradle bootRun > "$escapedLogName" 2>&1 &
else
  echo 'No se encontró un lanzador compatible para Java.' >&2
  exit 1
fi
''',
    };
  }

  /// Ejecuta script remoto mediante `sh -lc` y devuelve salida estándar.
  Future<String> _runCommand(SSHClient client, String script) async {
    final escapedScript = _escapeForSingleQuotes(script);
    final output = await client.run("sh -lc '$escapedScript'");
    return utf8.decode(output).trim();
  }

  /// Obtiene nombre base de una ruta remota.
  String _basename(String path) {
    if (path == '/') {
      return '/';
    }

    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final slashIndex = trimmed.lastIndexOf('/');
    if (slashIndex == -1) {
      return trimmed;
    }

    return trimmed.substring(slashIndex + 1);
  }

  /// Escapa comillas simples para scripts shell embebidos.
  String _escapeForSingleQuotes(String value) {
    return value.replaceAll("'", "'\"'\"'");
  }
}
