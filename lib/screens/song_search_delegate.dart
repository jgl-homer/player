import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../utils/title_utils.dart';

import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/song_list_tile.dart';

class SongSearchDelegate extends SearchDelegate<SongModel?> {
  final AudioProvider audioProvider;

  SongSearchDelegate(this.audioProvider);

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = AppTheme.darkTheme;
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: AppTheme.backgroundColor,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: AppTheme.textSecondary),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: AppTheme.textMain, fontSize: 18),
      ),
    );
  }

  @override
  String get searchFieldLabel => "Buscar canciones...";

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.isEmpty) {
      return Container(color: AppTheme.backgroundColor);
    }

    final results = audioProvider.allSongs.where((song) {
      final titleMatch = TitleUtils.getDisplayTitle(song).toLowerCase().contains(query.toLowerCase());
      final artistMatch = (song.artist ?? "").toLowerCase().contains(query.toLowerCase());
      return titleMatch || artistMatch;
    }).toList();

    if (results.isEmpty) {
      return Container(
        color: AppTheme.backgroundColor,
        child: const Center(
          child: Text("No se encontraron resultados", style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    return Container(
      color: AppTheme.backgroundColor,
      child: ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, index) {
          final song = results[index];
          final isSelected = audioProvider.currentSong?.id == song.id;

          return SongListTile(
            song: song,
            isSelected: isSelected,
            onTap: () {
              audioProvider.playPlaylist(results, index);
              close(context, song);
            },
          );
        },
      ),
    );
  }
}
