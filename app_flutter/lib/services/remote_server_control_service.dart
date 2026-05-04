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

  /// Inspecciona el directorio actual y subdirectorios hasta una profundidad configurable.
  Future<List<ManagedRemoteServer>> discoverServers({
    required String currentDirectory,
    required List<RemoteEntry> entries,
    int searchDepth = 1,
  }) async {
    return _withClient((client, sftp) async {
      final servers = <ManagedRemoteServer>[];
      final inspectedPaths = <String>{};
      final candidatePaths = await _collectCandidateDirectories(
        sftp: sftp,
        rootDirectory: currentDirectory,
        rootEntries: entries,
        maxDepth: searchDepth,
      );

      for (final candidate in candidatePaths) {
        if (!inspectedPaths.add(candidate.path)) {
          continue;
        }

        Set<String> markerFiles;
        try {
          markerFiles = await _listDirectoryNames(sftp, candidate.path);
        } catch (_) {
          continue;
        }

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
        final isRunning = await _isServerProcessRunning(
          client: client,
          directory: candidate.path,
          serverType: serverType,
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

  /// Recolecta directorios candidatos desde la raíz hasta `maxDepth` niveles.
  Future<List<({String name, String path})>> _collectCandidateDirectories({
    required SftpClient sftp,
    required String rootDirectory,
    required List<RemoteEntry> rootEntries,
    required int maxDepth,
  }) async {
    final normalizedDepth = maxDepth < 0 ? 0 : maxDepth;
    final pending = <({String name, String path, int depth})>[
      (name: _basename(rootDirectory), path: rootDirectory, depth: 0),
    ];
    final visitedPaths = <String>{rootDirectory};
    final candidates = <({String name, String path})>[];

    if (normalizedDepth >= 1) {
      for (final entry in rootEntries) {
        if (!entry.isDirectory || entry.isSymbolicLink) {
          continue;
        }
        if (!visitedPaths.add(entry.fullPath)) {
          continue;
        }
        pending.add((name: entry.name, path: entry.fullPath, depth: 1));
      }
    }

    for (var index = 0; index < pending.length; index++) {
      final current = pending[index];
      candidates.add((name: current.name, path: current.path));

      if (current.depth >= normalizedDepth) {
        continue;
      }

      List<({String name, String path})> children;
      try {
        children = await _listChildDirectories(sftp, current.path);
      } catch (_) {
        continue;
      }

      for (final child in children) {
        if (!visitedPaths.add(child.path)) {
          continue;
        }
        pending.add(
          (name: child.name, path: child.path, depth: current.depth + 1),
        );
      }
    }

    return candidates;
  }

  /// Arranca un servidor remoto según su tipo y estructura detectada.
  Future<void> startServer(ManagedRemoteServer server) async {
    await _withClient((client, sftp) async {
      await _runCommand(client, _buildStartCommand(server));
    });
  }

  /// Detiene procesos del proyecto detectados por directorio y stack.
  Future<void> stopServer(ManagedRemoteServer server) async {
    await _withClient((client, sftp) async {
      final escapedDirectory = _escapeForSingleQuotes(server.fullPath);
      final commandPattern = _resolveCommandPattern(server.type);
      await _runCommand(client, '''
target_dir=\$(readlink -f '$escapedDirectory' 2>/dev/null || printf '%s' '$escapedDirectory')
pids=\$(
  for proc in /proc/[0-9]*; do
    pid=\${proc#/proc/}
    cmd=\$(tr '\\0' ' ' < "\$proc/cmdline" 2>/dev/null || true)
    [ -z "\$cmd" ] && continue
    printf '%s' "\$cmd" | grep -Eq '$commandPattern' || continue
    cwd=\$(readlink -f "\$proc/cwd" 2>/dev/null || true)
    [ "\$cwd" = "\$target_dir" ] || continue
    printf '%s\n' "\$pid"
  done | sort -u
)

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

  /// Lista subdirectorios directos sin seguir enlaces simbólicos.
  Future<List<({String name, String path})>> _listChildDirectories(
    SftpClient sftp,
    String directory,
  ) async {
    final names = await sftp.listdir(directory);
    return names
        .where(
          (item) =>
              item.filename != '.' &&
              item.filename != '..' &&
              item.attr.isDirectory &&
              !item.attr.isSymbolicLink,
        )
        .map(
          (item) =>
              (name: item.filename, path: _joinRemotePath(directory, item.filename)),
        )
        .toList(growable: false);
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

  /// Comprueba si hay un proceso del proyecto ejecutándose en su directorio.
  Future<bool> _isServerProcessRunning({
    required SSHClient client,
    required String directory,
    required ManagedServerType serverType,
  }) async {
    final escapedDirectory = _escapeForSingleQuotes(directory);
    final commandPattern = _resolveCommandPattern(serverType);
    final output = await _runCommand(client, '''
target_dir=\$(readlink -f '$escapedDirectory' 2>/dev/null || printf '%s' '$escapedDirectory')
running='stopped'
for proc in /proc/[0-9]*; do
  cmd=\$(tr '\\0' ' ' < "\$proc/cmdline" 2>/dev/null || true)
  [ -z "\$cmd" ] && continue
  printf '%s' "\$cmd" | grep -Eq '$commandPattern' || continue
  cwd=\$(readlink -f "\$proc/cwd" 2>/dev/null || true)
  [ "\$cwd" = "\$target_dir" ] || continue
  running='running'
  break
done
printf '%s' "\$running"
''');
    return output.trim() == 'running';
  }

  /// Expresión regular para identificar procesos por stack.
  String _resolveCommandPattern(ManagedServerType serverType) {
    return switch (serverType) {
      ManagedServerType.nodeJs => r'(^|[[:space:]/])(node|npm|pnpm|yarn|bun)([[:space:]]|$)',
      ManagedServerType.java => r'(^|[[:space:]/])(java|mvn|gradle|mvnw|gradlew)([[:space:]]|$)',
    };
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

  /// Une segmentos de ruta remota con semántica POSIX.
  String _joinRemotePath(String parent, String child) {
    if (parent == '/') {
      return '/$child';
    }

    return '$parent/$child';
  }

  /// Escapa comillas simples para scripts shell embebidos.
  String _escapeForSingleQuotes(String value) {
    return value.replaceAll("'", "'\"'\"'");
  }
}
