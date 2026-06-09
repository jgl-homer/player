import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/song_list_tile.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import 'folder_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _selectedFilter = 'Todas';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);
    final query = _query.trim().toLowerCase();

    final filteredSongs = audioProvider.allSongs.where((song) {
      final titleMatch = song.title.toLowerCase().contains(query);
      final artistMatch = song.artist?.toLowerCase().contains(query) ?? false;
      final albumMatch = song.album?.toLowerCase().contains(query) ?? false;
      return titleMatch || artistMatch || albumMatch;
    }).toList();

    final filteredAlbums = audioProvider.allAlbums.where((album) {
      final titleMatch = album.album.toLowerCase().contains(query);
      final artistMatch = album.artist?.toLowerCase().contains(query) ?? false;
      return titleMatch || artistMatch;
    }).toList();

    final filteredArtists = audioProvider.allSongs
        .map((song) => song.artist)
        .whereType<String>()
        .where((artist) => artist.trim().isNotEmpty && artist != '<unknown>')
        .toSet()
        .where((artist) => artist.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final filteredFolders = audioProvider.sortedFolderPaths
        .where((folder) => folder.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar música',
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: Colors.grey, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        fillColor: AppTheme.surfaceColor,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  _filterChip('Todas'),
                  _filterChip('Canciones'),
                  _filterChip('Álbumes'),
                  _filterChip('Artistas'),
                  _filterChip('Carpetas'),
                ],
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? const _EmptySearchView()
                  : CustomScrollView(
                      slivers: [
                        if (_selectedFilter == 'Todas' ||
                            _selectedFilter == 'Canciones') ...[
                          _sectionHeader('Canciones', filteredSongs.length),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => SongListTile(
                                song: filteredSongs[index],
                                onTap: () => audioProvider.playPlaylist(
                                  filteredSongs,
                                  index,
                                ),
                              ),
                              childCount: filteredSongs.length,
                            ),
                          ),
                        ],
                        if (_selectedFilter == 'Todas' ||
                            _selectedFilter == 'Álbumes') ...[
                          _sectionHeader('Álbumes', filteredAlbums.length),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final album = filteredAlbums[index];
                                return _LibraryResultTile(
                                  title: album.album,
                                  subtitle:
                                      '${album.artist ?? 'Artista Desconocido'} • ${album.numOfSongs} canciones',
                                  artworkId: album.id,
                                  artworkType: ArtworkType.ALBUM,
                                  fallbackIcon: Icons.album,
                                  onTap: () => _openAlbum(
                                    context,
                                    audioProvider,
                                    album,
                                  ),
                                );
                              },
                              childCount: filteredAlbums.length,
                            ),
                          ),
                        ],
                        if (_selectedFilter == 'Todas' ||
                            _selectedFilter == 'Artistas') ...[
                          _sectionHeader('Artistas', filteredArtists.length),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final artistName = filteredArtists[index];
                                final artistSongs = audioProvider.allSongs
                                    .where((song) => song.artist == artistName)
                                    .toList();
                                final firstAlbumId = artistSongs.isNotEmpty
                                    ? artistSongs.first.albumId
                                    : null;
                                return _LibraryResultTile(
                                  title: artistName,
                                  subtitle: '${artistSongs.length} canciones',
                                  artworkId: firstAlbumId,
                                  artworkType: ArtworkType.ALBUM,
                                  fallbackIcon: Icons.person,
                                  onTap: () => _openArtist(
                                    context,
                                    audioProvider,
                                    artistName,
                                  ),
                                );
                              },
                              childCount: filteredArtists.length,
                            ),
                          ),
                        ],
                        if (_selectedFilter == 'Todas' ||
                            _selectedFilter == 'Carpetas') ...[
                          _sectionHeader('Carpetas', filteredFolders.length),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final folderPath = filteredFolders[index];
                                final folderName = folderPath.split('/').last;
                                return _LibraryResultTile(
                                  title: folderName,
                                  subtitle: folderPath,
                                  fallbackIcon: Icons.folder,
                                  onTap: () => _openFolder(
                                    context,
                                    audioProvider,
                                    folderName,
                                    folderPath,
                                  ),
                                );
                              },
                              childCount: filteredFolders.length,
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(String title, int count) {
    if (count == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(
          '$title ($count)',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedFilter = label),
        backgroundColor: Colors.transparent,
        selectedColor: AppTheme.primaryColor,
        labelStyle: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? AppTheme.primaryColor : AppTheme.surfaceVariant,
          ),
        ),
        showCheckmark: false,
      ),
    );
  }

  void _openArtist(
    BuildContext context,
    AudioProvider audioProvider,
    String artistName,
  ) {
    final artistSongs = audioProvider.allSongs
        .where((song) => song.artist == artistName)
        .toList();
    if (artistSongs.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArtistDetailScreen(
          artistName: artistName,
          songs: artistSongs,
        ),
      ),
    );
  }

  void _openAlbum(
    BuildContext context,
    AudioProvider audioProvider,
    AlbumModel album,
  ) {
    final albumSongs = audioProvider.allSongs
        .where((song) => song.albumId == album.id)
        .toList();
    if (albumSongs.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          albumName: album.album,
          albumId: album.id,
          songs: albumSongs,
        ),
      ),
    );
  }

  void _openFolder(
    BuildContext context,
    AudioProvider audioProvider,
    String folderName,
    String folderPath,
  ) {
    final folderSongs = audioProvider.allSongs.where((song) {
      final parts = song.data.split('/');
      if (parts.length <= 1) return false;
      final parent = parts.sublist(0, parts.length - 1).join('/');
      return parent == folderPath;
    }).toList();
    if (folderSongs.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderName: folderName,
          songs: folderSongs,
        ),
      ),
    );
  }
}

class _LibraryResultTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int? artworkId;
  final ArtworkType artworkType;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  const _LibraryResultTile({
    required this.title,
    required this.subtitle,
    this.artworkId,
    this.artworkType = ArtworkType.ALBUM,
    required this.fallbackIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: artworkId == null
            ? _FallbackArtwork(icon: fallbackIcon)
            : QueryArtworkWidget(
                id: artworkId!,
                type: artworkType,
                artworkHeight: 52,
                artworkWidth: 52,
                nullArtworkWidget: _FallbackArtwork(icon: fallbackIcon),
              ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  final IconData icon;

  const _FallbackArtwork({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      width: 52,
      color: AppTheme.surfaceColor,
      child: Icon(icon, color: Colors.grey),
    );
  }
}

class _EmptySearchView extends StatelessWidget {
  const _EmptySearchView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Busca por canción, artista o álbum',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}
