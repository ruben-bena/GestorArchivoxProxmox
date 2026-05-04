import 'package:flutter/material.dart';

/// Sidebar para alternar entre secciones principales del gestor remoto.
class ExplorerSidebar extends StatelessWidget {
  const ExplorerSidebar({
    super.key,
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final List<({String label, IconData icon})> sections;
  final String selectedSection;
  final ValueChanged<String> onSectionSelected;

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
                Icon(
                  Icons.dashboard_customize_outlined,
                  color: Colors.deepPurpleAccent,
                ),
                SizedBox(width: 8),
                Text(
                  'Explorador',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            ...sections.map((section) {
              // Marca visualmente el botón correspondiente a la sección activa.
              final isSelected = selectedSection == section.label;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onSectionSelected(section.label),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? Colors.deepPurpleAccent
                            : Colors.white24,
                      ),
                      backgroundColor: isSelected
                          ? Colors.deepPurple.withValues(alpha: 0.18)
                          : null,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(section.icon, color: Colors.deepPurpleAccent),
                    label: Text(section.label),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
