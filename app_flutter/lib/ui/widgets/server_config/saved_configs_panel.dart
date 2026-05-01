import 'package:flutter/material.dart';

import '../../../domain/server_connection_config.dart';

class SavedConfigsPanel extends StatelessWidget {
  const SavedConfigsPanel({
    super.key,
    required this.configs,
    required this.onConfigSelected,
    required this.onDeleteConfig,
  });

  final List<ServerConnectionConfig> configs;
  final ValueChanged<ServerConnectionConfig> onConfigSelected;
  final ValueChanged<ServerConnectionConfig> onDeleteConfig;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bookmark_outline, color: Colors.deepPurpleAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configuraciones guardadas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: configs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: Colors.black26,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Aún no hay configuraciones guardadas',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black38),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: configs.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final config = configs[index];

                        return ListTile(
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(config.name),
                          onTap: () => onConfigSelected(config),
                          trailing: IconButton(
                            onPressed: () => onDeleteConfig(config),
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.redAccent,
                            tooltip: 'Borrar configuración',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
