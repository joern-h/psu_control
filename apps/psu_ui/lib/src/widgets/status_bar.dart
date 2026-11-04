import 'package:flutter/material.dart';

import '../psu_connection.dart';

/// One-line connection status under the app bar.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.connection});

  final PsuConnection connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, text) = switch (connection) {
      final c when c.startingService => (
        Icons.hourglass_top_outlined,
        theme.colorScheme.secondary,
        'Starting psu_service …',
      ),
      final c when !c.serviceReachable => (
        Icons.cloud_off_outlined,
        theme.colorScheme.error,
        'Service not reachable at ${c.url}${c.lastError == null ? '' : ' (${c.lastError})'}',
      ),
      final c when !c.state.connected => (
        Icons.usb_off_outlined,
        theme.colorScheme.error,
        'Service running, power supply not connected${c.state.error == null ? '' : ' (${c.state.error})'}',
      ),
      final c => (
        Icons.check_circle_outline,
        const Color(0xFF0CA30C),
        c.state.identity ?? 'connected',
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
