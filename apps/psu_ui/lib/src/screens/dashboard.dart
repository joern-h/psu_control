import 'package:flutter/material.dart';

import '../presets.dart';
import '../psu_connection.dart';
import '../widgets/charts.dart';
import '../widgets/controls.dart';
import '../widgets/presets_panel.dart';
import '../widgets/readout.dart';
import '../widgets/status_bar.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.connection, required this.presets});

  final PsuConnection connection;
  final PresetStore presets;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final leftChildren = [
          Readout(state: connection.state, enabled: connection.psuConnected),
          const SizedBox(height: 12),
          Controls(connection: connection),
          const SizedBox(height: 12),
          PresetsPanel(connection: connection, store: presets),
        ];
        // The left column scrolls on its own so a long preset list never
        // pushes the charts around.
        final left = ListView(children: leftChildren);
        final charts = ChartsPanel(connection: connection);

        return Scaffold(
          appBar: AppBar(
            title: const Text('PSU Control'),
            actions: [
              IconButton(
                tooltip: 'Clear chart history',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: connection.history.isEmpty
                    ? null
                    : connection.clearHistory,
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: StatusBar(connection: connection),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 340, child: left),
                      const SizedBox(width: 16),
                      Expanded(child: charts),
                    ],
                  )
                : ListView(
                    children: [
                      ...leftChildren,
                      const SizedBox(height: 12),
                      SizedBox(height: 520, child: charts),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
