import 'package:flutter/material.dart';

void showFeedbackSnackbar(
  BuildContext context,
  String message, {
  required bool isSuccess,
  int durationSeconds = 2,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final indicatorColor = isSuccess ? Colors.green : Colors.red;

  messenger
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
