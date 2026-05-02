/// Utilidades para presentar metadatos de [RemoteEntry] en la interfaz.
class RemoteEntryFormatService {
  const RemoteEntryFormatService();

  /// Extrae el propietario del campo `longName` estilo `ls -l`.
  String? extractOwnerFromLongName(String longName) {
    final parts = longName.trim().split(RegExp(r'\s+'));
    return parts.length >= 4 ? parts[2] : null;
  }

  /// Extrae el grupo del campo `longName` estilo `ls -l`.
  String? extractGroupFromLongName(String longName) {
    final parts = longName.trim().split(RegExp(r'\s+'));
    return parts.length >= 5 ? parts[3] : null;
  }

  /// Convierte permisos binarios (`mode`) a formato simbólico Unix.
  String formatPermissionString(int? modeValue) {
    if (modeValue == null) {
      return 'No disponible';
    }

    final typeFlag = modeValue & 0xF000;
    final typePrefix = switch (typeFlag) {
      0x4000 => 'd',
      0xA000 => 'l',
      0x6000 => 'b',
      0x2000 => 'c',
      0x1000 => 'p',
      0xC000 => 's',
      _ => '-',
    };

    String bit(int value, int mask, String char) => (value & mask) != 0 ? char : '-';

    return '$typePrefix'
        '${bit(modeValue, 0x100, 'r')}${bit(modeValue, 0x80, 'w')}${bit(modeValue, 0x40, 'x')}'
        '${bit(modeValue, 0x20, 'r')}${bit(modeValue, 0x10, 'w')}${bit(modeValue, 0x8, 'x')}'
        '${bit(modeValue, 0x4, 'r')}${bit(modeValue, 0x2, 'w')}${bit(modeValue, 0x1, 'x')}';
  }

  /// Convierte permisos binarios (`mode`) a notación octal.
  String formatPermissionOctal(int? modeValue) {
    if (modeValue == null) {
      return '---';
    }

    return (modeValue & 0x1FF).toRadixString(8).padLeft(3, '0');
  }

  /// Formatea tamaño en unidades legibles (B/KB/MB/GB).
  String formatSize(int? size) {
    if (size == null) {
      return 'No disponible';
    }

    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Formatea timestamp Unix a fecha local legible.
  String formatUnixTime(int? unixSeconds) {
    if (unixSeconds == null) {
      return 'No disponible';
    }

    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
      isUtc: true,
    ).toLocal();

    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '${dateTime.year}-$month-$day $hour:$minute';
  }
}
