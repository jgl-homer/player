import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Servicio para guardar carátulas de álbumes como archivos temporales y
/// generar URIs válidos para usar en [MediaItem.artUri] de audio_service.
///
/// El sistema de notificaciones de Android requiere un URI accesible por el
/// proceso del sistema (file:// o content://). Los URIs de tipo
/// content://media/... fallan en Android 10+ cuando el proceso de notificación
/// no tiene acceso directo al ContentProvider.
class ArtworkCacheService {
  static const String _cacheSubdir = 'artwork_cache';
  static Directory? _cacheDir;

  /// Inicializa el directorio de caché de carátulas (llamar en init de app).
  static Future<void> init() async {
    final temp = await getTemporaryDirectory();
    _cacheDir = Directory('${temp.path}/$_cacheSubdir');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  /// Guarda [artworkBytes] como un archivo PNG temporal y retorna un
  /// [Uri] de tipo `file://` válido para [MediaItem.artUri].
  ///
  /// Usa el [songId] como clave de caché para evitar escrituras redundantes.
  /// Si el archivo ya existe y tiene contenido, retorna el URI en caché sin
  /// volver a escribir al disco.
  ///
  /// Retorna `null` si ocurre cualquier error, para que el caller pueda
  /// aplicar el fallback apropiado.
  static Future<Uri?> saveArtworkToTempFile(
    int songId,
    Uint8List artworkBytes, {
    bool overwrite = false,
  }) async {
    if (artworkBytes.isEmpty) return null;

    try {
      final dir = _cacheDir ?? await _ensureDir();
      final file = File('${dir.path}/artwork_$songId.png');

      // Reutilizar solo si overwrite es false, y el archivo existe y no está vacío
      if (!overwrite && await file.exists() && await file.length() > 0) {
        return file.uri;
      }

      await file.writeAsBytes(artworkBytes, flush: true);
      return file.uri;
    } catch (e) {
      debugPrint('[ArtworkCache] Error saving artwork for songId=$songId: $e');
      return null;
    }
  }

  static Future<File?> getArtworkFile(int songId) async {
    try {
      final dir = _cacheDir ?? await _ensureDir();
      final file = File('${dir.path}/artwork_$songId.png');
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Genera un URI `file://` a partir de bytes de artwork (Uint8List) usando
  /// un nombre de archivo derivado de un identificador único [key] (ej: ruta
  /// del archivo de audio o ID de canción).
  ///
  /// Útil cuando no se dispone de un ID numérico, o cuando la carátula viene
  /// de una fuente externa (ej: ID3 tag leída manualmente).
  static Future<Uri?> saveArtworkBytesToFile(
    String key,
    Uint8List artworkBytes,
  ) async {
    if (artworkBytes.isEmpty) return null;

    try {
      final dir = _cacheDir ?? await _ensureDir();
      // Sanitizar la clave para usarla como nombre de archivo
      final sanitizedKey = key
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
          .substring(0, key.length.clamp(0, 64));
      final file = File('${dir.path}/artwork_$sanitizedKey.png');

      if (await file.exists() && await file.length() > 0) {
        return file.uri;
      }

      await file.writeAsBytes(artworkBytes, flush: true);
      return file.uri;
    } catch (e) {
      debugPrint('[ArtworkCache] Error saving artwork for key=$key: $e');
      return null;
    }
  }

  /// Invalida la caché de un song específico (ej: al editar metadatos).
  static Future<void> invalidate(int songId) async {
    try {
      final dir = _cacheDir ?? await _ensureDir();
      final file = File('${dir.path}/artwork_$songId.png');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint(
          '[ArtworkCache] Error invalidating cache for songId=$songId: $e');
    }
  }

  /// Limpia toda la caché de carátulas temporales.
  static Future<void> clearAll() async {
    try {
      final dir = _cacheDir ?? await _ensureDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
    } catch (e) {
      debugPrint('[ArtworkCache] Error clearing artwork cache: $e');
    }
  }

  static Future<Directory> _ensureDir() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/$_cacheSubdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }
}
