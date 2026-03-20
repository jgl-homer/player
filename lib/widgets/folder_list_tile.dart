import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class FolderListTile extends StatelessWidget {
  final String folderName;
  final int songCount;
  final VoidCallback onTap;

  const FolderListTile({
    super.key,
    required this.folderName,
    required this.songCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      leading: Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const Icon(Icons.folder, color: Colors.grey, size: 30),
      ),
      title: Text(
        folderName,
        style: const TextStyle(
          color: AppTheme.textMain,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          "$songCount Canciones",
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
        color: AppTheme.surfaceColor,
        onSelected: (value) {
          // Implementar acciones como reproducir o añadir a la lista
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'reproducir',
            child: Text('Reproducir'),
          ),
          const PopupMenuItem<String>(
            value: 'añadir',
            child: Text('Añadir a lista'),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
