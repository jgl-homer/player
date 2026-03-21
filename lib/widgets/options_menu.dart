import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audiotags/audiotags.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/audio_provider.dart';

void showOptionsMenu(BuildContext context, AudioProvider audioProvider) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF222222),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return _OptionsMenuContent(audioProvider: audioProvider);
    },
  );
}

class _OptionsMenuContent extends StatelessWidget {
  final AudioProvider audioProvider;
  const _OptionsMenuContent({required this.audioProvider});

  @override
  Widget build(BuildContext context) {
    final song = audioProvider.currentSong;
    if (song == null) return const SizedBox.shrink();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: Colors.white, size: 28),
            title: const Text("Editor de etiquetas", style: TextStyle(color: Colors.white, fontSize: 18)),
            onTap: () {
              Navigator.pop(context);
              showDialog(context: context, builder: (context) => _EditTagDialog(provider: audioProvider));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
            title: const Text("Eliminar del dispositivo", style: TextStyle(color: Colors.redAccent, fontSize: 18)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteDialog(context, audioProvider);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, AudioProvider provider) {
    final song = provider.currentSong;
    if (song == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text("Confirmar eliminación", style: TextStyle(color: Colors.white)),
        content: Text("¿Eliminar '${song.title}' del dispositivo?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await provider.deleteSong(song);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? "Archivo eliminado correctamente." : "Error al eliminar. Verifica los permisos.",
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: success ? Colors.black87 : Colors.red,
                  ),
                );
              }
            },
            child: const Text("Eliminar", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

// ─── Full ID3 Tag Editor ──────────────────────────────────────────────────────

class _EditTagDialog extends StatefulWidget {
  final AudioProvider provider;
  const _EditTagDialog({required this.provider});

  @override
  State<_EditTagDialog> createState() => _EditTagDialogState();
}

class _EditTagDialogState extends State<_EditTagDialog> {
  late final TextEditingController _title;
  late final TextEditingController _album;
  late final TextEditingController _artist;
  late final TextEditingController _albumArtist;
  late final TextEditingController _composer;
  late final TextEditingController _genre;
  late final TextEditingController _year;
  late final TextEditingController _track;
  File? _newCoverFile;

  @override
  void initState() {
    super.initState();
    final song = widget.provider.currentSong!;
    final artistText = (song.artist == "<unknown>" || song.artist == null) ? "" : song.artist!;
    _title       = TextEditingController(text: song.title);
    _album       = TextEditingController(text: song.album ?? "");
    _artist      = TextEditingController(text: artistText);
    _albumArtist = TextEditingController();
    _composer    = TextEditingController();
    _genre       = TextEditingController(text: song.genre ?? "");
    // SongModel exposes `song.track` for tracking number
    _year        = TextEditingController();
    _track       = TextEditingController(text: song.track?.toString() ?? "");
  }

  @override
  void dispose() {
    for (final c in [_title, _album, _artist, _albumArtist, _composer, _genre, _year, _track]) c.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _newCoverFile = File(picked.path));
  }

  Future<void> _save() async {
    Navigator.pop(context);
    try {
      final song = widget.provider.currentSong!;
      List<Picture> pics = [];
      if (_newCoverFile != null) {
        final bytes = await _newCoverFile!.readAsBytes();
        pics = [Picture(bytes: bytes, pictureType: PictureType.coverFront, mimeType: MimeType.jpeg)];
      }
      final tag = Tag(
        title:   _title.text.isEmpty ? null : _title.text,
        album:   _album.text.isEmpty ? null : _album.text,
        artist:  _artist.text.isEmpty ? null : _artist.text,
        genre:   _genre.text.isEmpty ? null : _genre.text,
        year:    int.tryParse(_year.text),
        pictures: pics,
      );
      await AudioTags.write(song.data, tag);
      widget.provider.updateSongMetadata(_title.text, _artist.text);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Etiquetas guardadas en el archivo.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al guardar: $e", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
    }
  }

  Widget _field(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(color: Colors.grey),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text("Editor de etiquetas", style: TextStyle(color: Colors.white, fontSize: 22)),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cover art picker
              GestureDetector(
                onTap: _pickCover,
                child: Container(
                  width: 100, height: 100,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                    image: _newCoverFile != null ? DecorationImage(image: FileImage(_newCoverFile!), fit: BoxFit.cover) : null,
                  ),
                  child: _newCoverFile == null
                      ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_outlined, color: Colors.white60, size: 36),
                          SizedBox(height: 4),
                          Text("Cambiar imagen", style: TextStyle(color: Colors.white60, fontSize: 11), textAlign: TextAlign.center),
                        ])
                      : null,
                ),
              ),
              _field(_title, "Título"),
              _field(_album, "Álbum"),
              _field(_artist, "Artista"),
              _field(_albumArtist, "Artista del álbum"),
              _field(_composer, "Compositor"),
              _field(_genre, "Género"),
              _field(_year, "Año"),
              _field(_track, "Track (4 para la pista 4 o 2004 para CD 2, pista 4)"),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("cancelar", style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700]),
          child: const Text("Guardar", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
