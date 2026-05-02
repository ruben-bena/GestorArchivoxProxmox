import 'dart:convert';
import 'dart:io';

import '../domain/server_connection_config.dart';

/// Persiste y recupera configuraciones SSH desde un archivo JSON local.
class ConfigStorageService {
  const ConfigStorageService({this.configFilePath = '../configuraciones.json'});

  final String configFilePath;

  File get _configsFile => File(configFilePath);

  /// Lee todas las configuraciones válidas del archivo de almacenamiento.
  List<ServerConnectionConfig> readAll() {
    if (!_configsFile.existsSync()) {
      return [];
    }

    final content = _configsFile.readAsStringSync().trim();
    if (content.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => ServerConnectionConfig.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  /// Sobrescribe el archivo con el listado completo de configuraciones.
  void writeAll(List<ServerConnectionConfig> configs) {
    final encoded = const JsonEncoder.withIndent('  ').convert(
      configs.map((config) => config.toJson()).toList(),
    );
    _configsFile.writeAsStringSync(encoded);
  }

  /// Agrega una configuración al final del listado persistido.
  void add(ServerConnectionConfig config) {
    final configs = readAll()..add(config);
    writeAll(configs);
  }

  /// Elimina configuraciones que coincidan por identidad completa.
  void delete(ServerConnectionConfig config) {
    final configs = readAll();
    configs.removeWhere((savedConfig) => savedConfig.sameIdentityAs(config));
    writeAll(configs);
  }
}
