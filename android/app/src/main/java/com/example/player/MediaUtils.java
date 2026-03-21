package com.example.player;

import android.media.MediaMetadataRetriever;
import java.io.File;
import java.util.HashMap;
import java.util.Map;

public class MediaUtils {
    
    /**
     * Extrae TITLE y ARTIST de un archivo de audio.
     * Si no se encuentran etiquetas, devuelve el nombre del archivo como título.
     * 
     * @param path Ruta absoluta del archivo de audio.
     * @return Un mapa con las claves "title" y "artist".
     */
    public static Map<String, String> getSongMetadata(String path) {
        HashMap<String, String> metadata = new HashMap<>();
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        
        try {
            retriever.setDataSource(path);
            
            String title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE);
            String artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST);
            
            // Fallback si el título es nulo o vacío
            if (title == null || title.trim().isEmpty()) {
                File file = new File(path);
                title = file.getName(); // Usa el nombre del archivo (ej: cancion.mp3)
            }
            
            if (artist == null || artist.trim().isEmpty()) {
                artist = "Artista Desconocido";
            }
            
            metadata.put("title", title);
            metadata.put("artist", artist);
            
        } catch (Exception e) {
            e.printStackTrace();
            // Fallback total en caso de error
            File file = new File(path);
            metadata.put("title", file.getName());
            metadata.put("artist", "Desconocido");
        } finally {
            try {
                retriever.release();
            } catch (Exception e) {
                // Ignore release errors
            }
        }
        
        return metadata;
    }
}
