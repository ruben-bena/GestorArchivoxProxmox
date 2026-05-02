import 'package:flutter/material.dart';

/// Tipos de proyectos remotos soportados por el gestor.
enum ManagedServerType { nodeJs, java }

/// Extensión para centralizar la presentación visual por tipo de servidor.
extension ManagedServerTypePresentation on ManagedServerType {
  /// Nombre legible para UI.
  String get label {
    switch (this) {
      case ManagedServerType.nodeJs:
        return 'NodeJS';
      case ManagedServerType.java:
        return 'Java';
    }
  }

  /// Icono representativo para UI.
  IconData get icon {
    switch (this) {
      case ManagedServerType.nodeJs:
        return Icons.javascript_outlined;
      case ManagedServerType.java:
        return Icons.coffee_outlined;
    }
  }

  /// Color de acento para UI.
  Color get accentColor {
    switch (this) {
      case ManagedServerType.nodeJs:
        return Colors.greenAccent;
      case ManagedServerType.java:
        return Colors.orangeAccent;
    }
  }

  /// Puerto por defecto cuando no se puede detectar uno explícito.
  int get defaultPort {
    switch (this) {
      case ManagedServerType.nodeJs:
        return 3000;
      case ManagedServerType.java:
        return 8080;
    }
  }
}

/// Modelo de un servidor detectado dentro del sistema de archivos remoto.
class ManagedRemoteServer {
  const ManagedRemoteServer({
    required this.name,
    required this.fullPath,
    required this.type,
    required this.startCommandLabel,
    required this.detectedPort,
    required this.isRunning,
    this.forwardedLocalPort,
    this.forwardedRemotePort,
  });

  final String name;
  final String fullPath;
  final ManagedServerType type;
  final String startCommandLabel;
  final int detectedPort;
  final bool isRunning;
  final int? forwardedLocalPort;
  final int? forwardedRemotePort;

  /// Indica si existe un túnel local→remoto activo para este servidor.
  bool get hasActivePortForward {
    return forwardedLocalPort != null && forwardedRemotePort != null;
  }

  /// Devuelve una copia del servidor aplicando cambios parciales.
  ManagedRemoteServer copyWith({
    String? name,
    String? fullPath,
    ManagedServerType? type,
    String? startCommandLabel,
    int? detectedPort,
    bool? isRunning,
    int? forwardedLocalPort,
    int? forwardedRemotePort,
    bool clearForwardedLocalPort = false,
    bool clearForwardedRemotePort = false,
  }) {
    return ManagedRemoteServer(
      name: name ?? this.name,
      fullPath: fullPath ?? this.fullPath,
      type: type ?? this.type,
      startCommandLabel: startCommandLabel ?? this.startCommandLabel,
      detectedPort: detectedPort ?? this.detectedPort,
      isRunning: isRunning ?? this.isRunning,
      forwardedLocalPort: clearForwardedLocalPort
          ? null
          : (forwardedLocalPort ?? this.forwardedLocalPort),
      forwardedRemotePort: clearForwardedRemotePort
          ? null
          : (forwardedRemotePort ?? this.forwardedRemotePort),
    );
  }
}
