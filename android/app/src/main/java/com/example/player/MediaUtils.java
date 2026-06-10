package com.example.player;

import android.media.MediaMetadataRetriever;
import java.io.File;
import java.util.HashMap;
import java.util.Map;

public class MediaUtils {

    /**
     * Extrae metadata basica y tecnica de un archivo de audio.
     * Si no se encuentran etiquetas, devuelve el nombre del archivo como titulo.
     *
     * @param path Ruta absoluta del archivo de audio.
     * @return Un mapa con title, artist, bitrate, mimeType y format.
     */
    public static Map<String, String> getSongMetadata(String path) {
        HashMap<String, String> metadata = new HashMap<>();
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        File file = new File(path);
        String format = getFileExtension(file);

        try {
            retriever.setDataSource(path);

            String title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE);
            String artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST);
            String bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE);
            String mimeType = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE);

            if (title == null || title.trim().isEmpty()) {
                title = file.getName();
            }

            if (artist == null || artist.trim().isEmpty()) {
                artist = "Artista Desconocido";
            }

            metadata.put("title", title);
            metadata.put("artist", artist);
            metadata.put("bitrate", bitrate == null ? "" : bitrate);
            metadata.put("mimeType", mimeType == null ? "" : mimeType);
            metadata.put("format", format);
        } catch (Exception e) {
            e.printStackTrace();
            metadata.put("title", file.getName());
            metadata.put("artist", "Desconocido");
            metadata.put("bitrate", "");
            metadata.put("mimeType", "");
            metadata.put("format", format);
        } finally {
            try {
                retriever.release();
            } catch (Exception e) {
                // Ignore release errors
            }
        }

        return metadata;
    }

    private static String getFileExtension(File file) {
        String name = file.getName();
        int dotIndex = name.lastIndexOf('.');
        if (dotIndex < 0 || dotIndex == name.length() - 1) {
            return "";
        }
        return name.substring(dotIndex + 1).toUpperCase();
    }
}
