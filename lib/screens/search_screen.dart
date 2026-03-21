import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/song_list_tile.dart';
import 'folder_detail_screen.dart';
import 'artist_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  String _query = "";
  String _selectedFilter = "Todas";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);

    // Filtering logic
    final filteredSongs = audioProvider.allSongs.where((s) =>
        s.title.toLowerCase().contains(_query.toLowerCase()) ||
        (s.artist?.toLowerCase().contains(_query.toLowerCase()) ?? false)).toList();

    final filteredAlbums = audioProvider.allAlbums.where((a) =>
        a.album.toLowerCase().contains(_query.toLowerCase()) ||
        (a.artist?.toLowerCase().contains(_query.toLowerCase()) ?? false)).toList();

    final filteredArtists = audioProvider.allSongs
        .map((s) => s.artist)
        .whereType<String>()
        .toSet()
        .where((artist) => artist.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    final filteredFolders = audioProvider.sortedFolderPaths.where((f) =>
        f.toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "primer",
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: _query.isNotEmpty 
                          ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey, size: 20), onPressed: () {
                              _searchController.clear();
                              setState(() => _query = "");
                            })
                          : null,
                        fillColor: const Color(0xFF1E1E1E),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) => setState(() => _query = val),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("cancelar", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryColor,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: "Audio"),
              ],
            ),

            // Filter Chips (Only for Audio)
            if (_tabController.index == 0)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    _filterChip("Todas"),
                    _filterChip("Canciones"),
                    _filterChip("Álbumes"),
                    _filterChip("Artistas"),
                    _filterChip("Carpetas"),
                  ],
                ),
              ),

            // Results List
            Expanded(
              child: _tabController.index != 0 
                ? const Center(child: Text("Sin resultados en esta categoría", style: TextStyle(color: Colors.grey)))
                : _query.isEmpty 
                  ? const Center(child: Text("Busca tus canciones favoritas", style: TextStyle(color: Colors.grey)))
                  : CustomScrollView(
                      slivers: [
                        // Canciones Section
                        if (_selectedFilter == "Todas" || _selectedFilter == "Canciones") ...[
                          _buildSliverSectionHeader("Canciones", filteredSongs.length),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => SongListTile(
                                song: filteredSongs[index],
                                onTap: () => audioProvider.playPlaylist(filteredSongs, index),
                              ),
                              childCount: filteredSongs.length,
                            ),
                          ),
                        ],
                        
                        // Álbumes Section
                        if (_selectedFilter == "Todas" || _selectedFilter == "Álbumes") ...[
                          _buildSliverSectionHeader("Álbumes", filteredAlbums.length),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 200,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: filteredAlbums.length,
                                itemBuilder: (context, index) {
                                  final album = filteredAlbums[index];
                                  return GestureDetector(
                                    onTap: () => _openAlbum(context, audioProvider, album),
                                    child: _buildAlbumCard(album),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],

                        // Artistas Section
                        if (_selectedFilter == "Todas" || _selectedFilter == "Artistas") ...[
                          _buildSliverSectionHeader("Artistas", filteredArtists.length),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final artistName = filteredArtists[index];
                                return ListTile(
                                  leading: const Icon(Icons.person, color: Colors.grey),
                                  title: Text(artistName, style: const TextStyle(color: Colors.white)),
                                  onTap: () => _openArtist(context, audioProvider, artistName),
                                );
                              },
                              childCount: filteredArtists.length,
                            ),
                          ),
                        ],

                        // Carpetas Section
                        if (_selectedFilter == "Todas" || _selectedFilter == "Carpetas") ...[
                          _buildSliverSectionHeader("Carpetas", filteredFolders.length),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final folderPath = filteredFolders[index];
                                final folderName = folderPath.split('/').last;
                                return ListTile(
                                  leading: const Icon(Icons.folder, color: Colors.grey),
                                  title: Text(folderName, style: const TextStyle(color: Colors.white)),
                                  subtitle: Text(folderPath, style: const TextStyle(color: Colors.grey, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => _openFolder(context, audioProvider, folderName, folderPath),
                                );
                              },
                              childCount: filteredFolders.length,
                            ),
                          ),
                        ],
                        
                        const SliverToBoxAdapter(child: SizedBox(height: 100)), // Space for mini player
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverSectionHeader(String title, int count) {
    if (count == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: ListTile(
        title: Text("$title ($count)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildAlbumCard(AlbumModel album) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: QueryArtworkWidget(
              id: album.id,
              type: ArtworkType.ALBUM,
              nullArtworkWidget: Container(
                color: Colors.grey[800],
                width: 140, height: 140,
                child: const Icon(Icons.music_note, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(album.album, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(album.artist ?? "Unknown", style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  void _openArtist(BuildContext context, AudioProvider audioProvider, String artistName) {
    final artistSongs = audioProvider.allSongs.where((s) => s.artist == artistName).toList();
    if (artistSongs.isNotEmpty) {
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
  }

  void _openAlbum(BuildContext context, AudioProvider audioProvider, AlbumModel album) {
    final albumSongs = audioProvider.allSongs.where((s) => s.albumId == album.id).toList();
    if (albumSongs.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArtistDetailScreen( // ArtistDetailScreen already handles album groupings
            artistName: album.artist ?? "Desconocido",
            songs: albumSongs,
          ),
        ),
      );
    }
  }

  void _openFolder(BuildContext context, AudioProvider audioProvider, String folderName, String folderPath) {
    final folderSongs = audioProvider.allSongs.where((song) {
      final parts = song.data.split('/');
      if (parts.length > 1) {
        final parent = parts.sublist(0, parts.length - 1).join('/');
        return parent == folderPath;
      }
      return false;
    }).toList();

    if (folderSongs.isNotEmpty) {
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

  Widget _filterChip(String label) {
    bool isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) => setState(() => _selectedFilter = label),
        backgroundColor: Colors.transparent,
        selectedColor: Colors.white,
        labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
        shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.white : Colors.grey[700]!)),
        showCheckmark: false,
      ),
    );
  }
}

class _Section extends StatefulWidget {
  final String title;
  final int count;
  final Widget child;

  const _Section({required this.title, required this.count, required this.child});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return const SizedBox.shrink();
    return Column(
      children: [
        ListTile(
          title: Text("${widget.title} (${widget.count})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          trailing: Icon(_isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
        ),
        if (_isExpanded) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: widget.child,
        ),
      ],
    );
  }
}
