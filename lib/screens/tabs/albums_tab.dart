import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../../providers/audio_provider.dart';
import '../../../theme/app_theme.dart';

class AlbumsTab extends StatelessWidget {
  const AlbumsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);

    return FutureBuilder<List<AlbumModel>>(
      future: audioProvider.audioQuery.queryAlbums(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final albums = snapshot.data!;

        return ListView.builder(
          itemCount: albums.length,
          itemBuilder: (context, index) {
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: QueryArtworkWidget(
                  id: albums[index].id,
                  type: ArtworkType.ALBUM,
                  artworkHeight: 50,
                  artworkWidth: 50,
                  nullArtworkWidget: Container(
                    height: 50,
                    width: 50,
                    color: Colors.grey[800],
                    child: const Icon(Icons.album, color: Colors.grey),
                  ),
                ),
              ),
              title: Text(
                albums[index].album,
                style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                "${albums[index].artist ?? "Desconocido"} • ${albums[index].numOfSongs} Canciones",
                style: const TextStyle(color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        );
      },
    );
  }
}
