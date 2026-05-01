import 'package:flutter/material.dart';

import '../../domain/server_connection_config.dart';
import '../../services/config_storage_service.dart';
import '../../services/ssh_connection_service.dart';
import '../widgets/server_config/connection_form_panel.dart';
import '../widgets/server_config/saved_configs_panel.dart';
import '../widgets/shared/processing_overlay.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final GlobalKey<ConnectionFormPanelState> _formKey =
      GlobalKey<ConnectionFormPanelState>();
  final ConfigStorageService _configStorageService = const ConfigStorageService();
  final SshConnectionService _sshConnectionService = const SshConnectionService();

  List<ServerConnectionConfig> _savedConfigs = [];
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _reloadSavedConfigs();
  }

  void _reloadSavedConfigs() {
    setState(() {
      _savedConfigs = _configStorageService.readAll();
    });
  }

  void _selectConfig(ServerConnectionConfig config) {
    _formKey.currentState?.loadConfig(config);
  }

  void _deleteConfig(ServerConnectionConfig config) {
    _configStorageService.delete(config);
    _reloadSavedConfigs();
  }

  void _setConnectingState(bool isConnecting) {
    if (_isConnecting == isConnecting) {
      return;
    }

    setState(() {
      _isConnecting = isConnecting;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración Proxmox')),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isConnecting,
            child: const SizedBox.expand(),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: SavedConfigsPanel(
                    configs: _savedConfigs,
                    onConfigSelected: _selectConfig,
                    onDeleteConfig: _deleteConfig,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: ConnectionFormPanel(
                    key: _formKey,
                    onFavoriteAdded: _reloadSavedConfigs,
                    onConnectingStateChanged: _setConnectingState,
                    configStorageService: _configStorageService,
                    sshConnectionService: _sshConnectionService,
                  ),
                ),
              ],
            ),
          ),
          if (_isConnecting)
            const ProcessingOverlay(label: 'Conectando por SSH...'),
        ],
      ),
    );
  }
}
