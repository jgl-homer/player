import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Servicio para acceder y modificar archivos en almacenamiento externo (SD Card)
/// usando el Storage Access Framework (SAF) de Android vía MethodChannel.
///
/// En Android 10+ (API 29+) las rutas /storage/XXXX-XXXX/ son Scoped Storage:
/// no se pueden escribir con File() directamente aunque tengas WRITE_EXTERNAL_STORAGE.
/// La solución correcta es solicitar acceso a la carpeta raíz de la SD Card
/// mediante SAF (ACTION_OPEN_DOCUMENT_TREE) y luego operar con Document URIs.
class SdCardAccessService {
  static const MethodChannel _channel =
      MethodChannel('com.jglhomer.player/saf_utils');

  /// Solicita al usuario que seleccione la carpeta raíz de la SD Card
  /// mediante el picker de SAF (ACTION_OPEN_DOCUMENT_TREE).
  ///
  /// Retorna el URI de árbol (tree URI) concedido como String, ej:
  /// `content://com.android.externalstorage.documents/tree/XXXX-XXXX%3A`
  /// Retorna `null` si el usuario cancela o falla el proceso.
  static Future<String?> requestSdCardAccess() async {
    try {
      final result = await _channel.invokeMethod<String>('requestSdCardAccess');
      return result;
    } catch (e) {
      debugPrint('[SAF] Error requesting SD card access: $e');
      return null;
    }
  }

  /// Verifica si ya tenemos permiso persistente sobre el [treeUri] dado.
  static Future<bool> hasPersistedPermission(String treeUri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasPersistedPermission',
        {'treeUri': treeUri},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[SAF] Error checking persisted permission: $e');
      return false;
    }
  }

  /// Retorna el treeUri persistido previamente (si existe), o null.
  static Future<String?> getPersistedTreeUri() async {
    try {
      final result = await _channel.invokeMethod<String>('getPersistedTreeUri');
      return result;
    } catch (e) {
      debugPrint('[SAF] Error getting persisted tree URI: $e');
      return null;
    }
  }

  /// Escribe [bytes] en el archivo ubicado en [filePath] (ruta absoluta
  /// /storage/XXXX-XXXX/...) usando el SAF.
  ///
  /// Requiere haber llamado [requestSdCardAccess] previamente y que el
  /// treeUri esté persistido en el sistema.
  ///
  /// Retorna `true` si la escritura fue exitosa.
  static Future<bool> writeFileViaSaf(String filePath, Uint8List bytes) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'writeFileViaSaf',
        {
          'filePath': filePath,
          'bytes': bytes,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[SAF] Error writing file via SAF: $e');
      return false;
    }
  }

  /// Escribe [bytes] directamente usando un Document URI SAF ya conocido.
  /// Útil si tienes el URI exacto del documento (content://...).
  static Future<bool> writeByDocumentUri(
    String documentUri,
    Uint8List bytes,
  ) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'writeByDocumentUri',
        {
          'documentUri': documentUri,
          'bytes': bytes,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[SAF] Error writing by document URI: $e');
      return false;
    }
  }

  /// Verifica si una ruta de archivo está en una SD Card / volumen externo
  /// (es decir, fuera del almacenamiento interno principal).
  static bool isExternalStoragePath(String filePath) {
    // El almacenamiento interno principal suele ser /storage/emulated/0/
    // Los volúmenes externos (SD) siguen el patrón /storage/XXXX-XXXX/
    if (!filePath.startsWith('/storage/')) return false;
    final parts = filePath.split('/');
    if (parts.length < 3) return false;
    final volume = parts[2]; // ej: "emulated", "ABCD-1234"
    return volume != 'emulated';
  }

  /// Helper de alto nivel: intenta escribir en [filePath].
  /// - Si el archivo está en almacenamiento interno → usa File() directamente.
  /// - Si está en SD Card → usa SAF.
  /// - Si SAF no tiene permiso persistido → solicita acceso al usuario primero.
  ///
  /// Retorna `true` si la escritura fue exitosa, `false` en caso contrario.
  static Future<bool> writeFileWithFallback(
    String filePath,
    Uint8List bytes, {
    /// Callback opcional llamado antes de mostrar el picker de SAF,
    /// útil para mostrar un diálogo explicativo al usuario.
    Future<bool> Function()? onNeedsPermission,
  }) async {
    if (!isExternalStoragePath(filePath)) {
      // Almacenamiento interno: escritura directa
      try {
        final file = File(filePath);
        await file.writeAsBytes(bytes, flush: true);
        return true;
      } catch (e) {
        debugPrint('[SAF] Error writing to internal storage: $e');
        return false;
      }
    }

    // Almacenamiento externo: necesitamos SAF
    final persistedUri = await getPersistedTreeUri();
    bool hasAccess =
        persistedUri != null && await hasPersistedPermission(persistedUri);

    if (!hasAccess) {
      // Preguntar al usuario si quiere conceder acceso
      if (onNeedsPermission != null) {
        final proceed = await onNeedsPermission();
        if (!proceed) return false;
      }
      final newUri = await requestSdCardAccess();
      if (newUri == null) return false;
      hasAccess = true;
    }

    return writeFileViaSaf(filePath, bytes);
  }
}
