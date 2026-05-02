/// Representa un archivo/carpeta remota obtenida por SFTP.
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
    required this.isSymbolicLink,
    required this.longName,
    this.modeValue,
    this.userId,
    this.groupId,
    this.size,
    this.modifyTime,
  });

  final String name;
  final String fullPath;
  final bool isDirectory;
  final bool isSymbolicLink;
  final String longName;
  final int? modeValue;
  final int? userId;
  final int? groupId;
  final int? size;
  final int? modifyTime;

  /// Etiqueta de tipo usada en la UI.
  String get typeLabel {
    if (isDirectory) {
      return 'Carpeta';
    }
    if (isSymbolicLink) {
      return 'Enlace simbólico';
    }
    return 'Archivo';
  }

  /// Crea una copia con metadatos opcionalmente actualizados o limpiados.
  RemoteEntry copyWith({
    int? modeValue,
    int? userId,
    int? groupId,
    int? size,
    int? modifyTime,
    bool clearModeValue = false,
    bool clearUserId = false,
    bool clearGroupId = false,
    bool clearSize = false,
    bool clearModifyTime = false,
  }) {
    return RemoteEntry(
      name: name,
      fullPath: fullPath,
      isDirectory: isDirectory,
      isSymbolicLink: isSymbolicLink,
      longName: longName,
      modeValue: clearModeValue ? null : (modeValue ?? this.modeValue),
      userId: clearUserId ? null : (userId ?? this.userId),
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      size: clearSize ? null : (size ?? this.size),
      modifyTime: clearModifyTime ? null : (modifyTime ?? this.modifyTime),
    );
  }
}
