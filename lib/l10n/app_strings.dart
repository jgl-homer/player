import 'package:flutter/widgets.dart';

class AppStrings {
  static const _values = <String, Map<String, String>>{
    'es': {
      'folders': 'Carpetas',
      'songs': 'Canciones',
      'favorites': 'Favoritos',
      'albums': 'Álbumes',
      'artists': 'Artistas',
      'playlists': 'Playlists',
      'recently_added': 'Recientes',
      'most_played': 'Más reproducidas',
      'settings': 'Configuración',
      'refresh_library': 'Refrescar biblioteca',
      'play_next': 'Reproducir a continuación',
      'add_queue': 'Añadir a la cola',
      'add_playlist': 'Añadir a playlist',
      'go_album': 'Ir al álbum',
      'go_artist': 'Ir al artista',
      'youtube': 'Buscar en YouTube',
      'details': 'Información y detalles',
      'tag_editor': 'Editor de etiquetas',
      'hide_library': 'Ocultar de la biblioteca',
      'share': 'Compartir',
      'delete_device': 'Eliminar del dispositivo',
    },
    'en': {
      'folders': 'Folders',
      'songs': 'Songs',
      'favorites': 'Favorites',
      'albums': 'Albums',
      'artists': 'Artists',
      'playlists': 'Playlists',
      'recently_added': 'Recent',
      'most_played': 'Most played',
      'settings': 'Settings',
      'refresh_library': 'Refresh library',
      'play_next': 'Play next',
      'add_queue': 'Add to queue',
      'add_playlist': 'Add to playlist',
      'go_album': 'Go to album',
      'go_artist': 'Go to artist',
      'youtube': 'Find on YouTube',
      'details': 'Information and details',
      'tag_editor': 'Tag editor',
      'hide_library': 'Hide from library',
      'share': 'Share',
      'delete_device': 'Delete from device',
    },
    'pt': {
      'folders': 'Pastas',
      'songs': 'Músicas',
      'favorites': 'Favoritos',
      'albums': 'Álbuns',
      'artists': 'Artistas',
      'playlists': 'Playlists',
      'recently_added': 'Recentes',
      'most_played': 'Mais tocadas',
      'settings': 'Configurações',
      'refresh_library': 'Atualizar biblioteca',
      'play_next': 'Tocar em seguida',
      'add_queue': 'Adicionar à fila',
      'add_playlist': 'Adicionar à playlist',
      'go_album': 'Ir para o álbum',
      'go_artist': 'Ir para o artista',
      'youtube': 'Buscar no YouTube',
      'details': 'Informações e detalhes',
      'tag_editor': 'Editor de tags',
      'hide_library': 'Ocultar da biblioteca',
      'share': 'Compartilhar',
      'delete_device': 'Excluir do dispositivo',
    },
  };

  static String of(BuildContext context, String key) {
    final code = Localizations.localeOf(context).languageCode;
    return _values[code]?[key] ?? _values['es']![key] ?? key;
  }
}

extension AppTranslations on BuildContext {
  String tr(String key) => AppStrings.of(this, key);
}
