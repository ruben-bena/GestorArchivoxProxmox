import 'package:flutter/material.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _hostController = TextEditingController(text: "ieticloudpro.ieti.cat");
  final _userController = TextEditingController(text: "usuario");
  final _portController = TextEditingController(text: "22");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configuración Proxmox")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Panel izquierdo: lista de configuraciones guardadas ──
            Expanded(
              flex: 2,
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.bookmark_outline,
                              color: Colors.deepPurpleAccent),
                          SizedBox(width: 8),
                          Text(
                            "Configuraciones guardadas",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Espacio reservado — se llenará próximamente
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.inbox_outlined,
                                  size: 48,
                                  color: Colors.black26),
                              SizedBox(height: 12),
                              Text(
                                "Aún no hay configuraciones guardadas",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black38),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 24),

            // ── Panel derecho: formulario de conexión ──
            Expanded(
              flex: 3,
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.dns,
                          size: 80, color: Colors.deepPurpleAccent),
                      const SizedBox(height: 32),

                      // Campo: Host
                      TextField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Dirección IP o Host',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lan),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Campo: Usuario
                      TextField(
                        controller: _userController,
                        decoration: const InputDecoration(
                          labelText: 'Usuario SSH',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Botón de Conectar
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.bolt),
                          label: const Text(
                            "CONECTAR AL SERVIDOR",
                            style: TextStyle(fontSize: 16),
                          ),
                          onPressed: () {
                            // Aquí llamarás a tu SSHManager en el futuro
                            _intentarConexion();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _intentarConexion() {
    // TODO
  }
}