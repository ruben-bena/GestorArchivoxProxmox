import 'package:flutter/material.dart';

/// Muestra un `SnackBar` unificado con indicador visual de éxito/error.
void showFeedbackSnackbar(
  BuildContext context,
  String message, {
  required bool isSuccess,
  int durationSeconds = 2,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  // Punto visual rápido para distinguir éxito y error sin leer el texto completo.
  final indicatorColor = isSuccess ? Colors.green : Colors.red;

  messenger
    // Se limpia la cola para mostrar siempre el último resultado relevante.
    ..hideCurrentSnackBar()
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: indicatorColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        showCloseIcon: true,
        closeIconColor: theme.colorScheme.onSurface,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: durationSeconds),
      ),
    );
}
