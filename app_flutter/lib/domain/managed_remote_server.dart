import 'package:flutter/material.dart';

enum ManagedServerType { nodeJs, java }

extension ManagedServerTypePresentation on ManagedServerType {
  String get label {
    switch (this) {
      case ManagedServerType.nodeJs:
        return 'NodeJS';
      case ManagedServerType.java:
        return 'Java';
    }
  }

  IconData get icon {
    switch (this) {
      case ManagedServerType.nodeJs:
        return Icons.javascript_outlined;
      case ManagedServerType.java:
        return Icons.coffee_outlined;
    }
  }

  Color get accentColor {
    switch (this) {
      case ManagedServerType.nodeJs:
        return Colors.greenAccent;
      case ManagedServerType.java:
        return Colors.orangeAccent;
    }
  }

  int get defaultPort {
    switch (this) {
      case ManagedServerType.nodeJs:
        return 3000;
      case ManagedServerType.java:
        return 8080;
    }
  }
}

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

  bool get hasActivePortForward {
    return forwardedLocalPort != null && forwardedRemotePort != null;
  }

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
