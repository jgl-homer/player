package com.jglhomer.player;

import android.media.MediaMetadataRetriever;
import android.util.Log;
import com.arthenica.ffmpegkit.FFprobeKit;
import com.arthenica.ffmpegkit.MediaInformation;
import com.arthenica.ffmpegkit.MediaInformationSession;
import com.arthenica.ffmpegkit.StreamInformation;
import java.io.File;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class MediaUtils {
    private static final Map<String, Map<String, String>> WMA_METADATA_CACHE = new ConcurrentHashMap<>();

    /**
     * Extrae metadata básica y técnica completa de un archivo de audio.
     *
     * @param path Ruta absoluta del archivo de audio.
     * @return Un mapa con title, artist, albumArtist, album, composer, genre, year,
     *         track, bitrate, mimeType, sampleRate, bitsPerSample, y format.
     */
    public static Map<String, String> getSongMetadata(String path) {
        HashMap<String, String> metadata = new HashMap<>();
        File file = new File(path);
        String format = getFileExtension(file);

        metadata.put("title", file.getName());
        metadata.put("artist", "Desconocido");
        metadata.put("albumArtist", "Desconocido");
        metadata.put("album", "Desconocido");
        metadata.put("composer", "Desconocido");
        metadata.put("genre", "Desconocido");
        metadata.put("year", "Desconocido");
        metadata.put("track", "Desconocido");
        metadata.put("bitrate", "0");
        metadata.put("mimeType", "Desconocido");
        metadata.put("sampleRate", "0");
        metadata.put("bitsPerSample", "0");
        metadata.put("duration", "0");
        metadata.put("format", format);

        if ("WMA".equals(format)) {
            String cacheKey = path + ":" + file.length() + ":" + file.lastModified();
            Map<String, String> cached = WMA_METADATA_CACHE.get(cacheKey);
            if (cached != null) {
                return new HashMap<>(cached);
            }

            Map<String, String> result = getWmaMetadata(path, file, metadata);
            WMA_METADATA_CACHE.put(cacheKey, new HashMap<>(result));
            return result;
        }

        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
            retriever.setDataSource(path);

            String title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE);
            String artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST);
            String albumArtist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST);
            String album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM);
            String composer = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_COMPOSER);
            String genre = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE);
            String year = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR);
            if (year == null || year.isEmpty()) {
                year = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE);
            }
            String track = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER);
            String bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE);
            String mimeType = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE);
            String duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);

            String sampleRate = null;
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                sampleRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE);
            }

            String bitsPerSample = null;
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                bitsPerSample = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITS_PER_SAMPLE);
            }

            metadata.put("title", title != null ? title : file.getName());
            metadata.put("artist", artist != null ? artist : "Artista Desconocido");
            metadata.put("albumArtist", albumArtist != null ? albumArtist : "");
            metadata.put("album", album != null ? album : "");
            metadata.put("composer", composer != null ? composer : "");
            metadata.put("genre", genre != null ? genre : "");
            metadata.put("year", year != null ? year : "");
            metadata.put("track", track != null ? track : "");
            metadata.put("bitrate", bitrate != null ? bitrate : "");
            metadata.put("mimeType", mimeType != null ? mimeType : "");
            metadata.put("duration", duration != null ? duration : "0");
            metadata.put("sampleRate", sampleRate != null ? sampleRate : "");
            metadata.put("bitsPerSample", bitsPerSample != null ? bitsPerSample : "");
            metadata.put("format", format);
        } catch (IllegalArgumentException e) {
            Log.w("MediaUtils", "No se pudo leer metadata de: " + path, e);
        } catch (RuntimeException e) {
            Log.w("MediaUtils", "Error leyendo metadata de: " + path, e);
        } finally {
            try {
                retriever.release();
            } catch (Exception e) {
                Log.w("MediaUtils", "No se pudo liberar MediaMetadataRetriever", e);
            }
        }

        return metadata;
    }

    public static String getEmbeddedLyrics(String path) {
        try {
            MediaInformationSession session = FFprobeKit.getMediaInformation(path);
            MediaInformation information = session.getMediaInformation();
            if (information == null || information.getTags() == null) {
                return null;
            }
            org.json.JSONObject tags = information.getTags();
            String[] keys = { "lyrics", "unsyncedlyrics", "unsynchronised_lyrics" };
            for (String key : keys) {
                String value = tag(tags, key);
                if (value != null && !value.trim().isEmpty()) {
                    return value.trim();
                }
            }
        } catch (Exception e) {
            Log.w("MediaUtils", "No se pudieron leer letras incrustadas: " + path, e);
        }
        return null;
    }

    private static Map<String, String> getWmaMetadata(
            String path, File file, HashMap<String, String> metadata) {
        try {
            MediaInformationSession session = FFprobeKit.getMediaInformation(path);
            MediaInformation information = session.getMediaInformation();
            if (information == null) {
                Log.w("MediaUtils", "FFprobe no devolvió metadata para: " + path);
                return metadata;
            }

            org.json.JSONObject tags = information.getTags();
            putIfPresent(metadata, "title", tag(tags, "title"), file.getName());
            putIfPresent(metadata, "artist", tag(tags, "artist"), "Artista Desconocido");
            putIfPresent(metadata, "albumArtist", firstTag(tags, "album_artist", "albumartist"), "");
            putIfPresent(metadata, "album", tag(tags, "album"), "");
            putIfPresent(metadata, "composer", tag(tags, "composer"), "");
            putIfPresent(metadata, "genre", tag(tags, "genre"), "");
            putIfPresent(metadata, "year", firstTag(tags, "date", "year"), "");
            putIfPresent(metadata, "track", firstTag(tags, "track", "tracknumber"), "");
            putIfPresent(metadata, "bitrate", information.getBitrate(), "");
            putIfPresent(metadata, "duration", information.getDuration(), "0");
            putIfPresent(metadata, "mimeType", "audio/x-ms-wma", "");

            if (information.getStreams() != null) {
                for (StreamInformation stream : information.getStreams()) {
                    if ("audio".equals(stream.getType())) {
                        putIfPresent(metadata, "sampleRate", stream.getSampleRate(), "");
                        break;
                    }
                }
            }
        } catch (Exception e) {
            Log.w("MediaUtils", "No se pudo leer metadata WMA con FFprobe: " + path, e);
        }
        return metadata;
    }

    private static String tag(org.json.JSONObject tags, String key) {
        if (tags == null) return null;
        String direct = tags.optString(key, null);
        if (direct != null && !direct.isEmpty()) return direct;

        java.util.Iterator<String> keys = tags.keys();
        while (keys.hasNext()) {
            String candidate = keys.next();
            if (candidate != null && candidate.equalsIgnoreCase(key)) {
                String value = tags.optString(candidate, null);
                if (value != null && !value.isEmpty()) return value;
            }
        }
        return null;
    }

    private static String firstTag(org.json.JSONObject tags, String first, String second) {
        String value = tag(tags, first);
        return value != null && !value.isEmpty() ? value : tag(tags, second);
    }

    private static void putIfPresent(
            Map<String, String> metadata, String key, String value, String fallback) {
        metadata.put(key, value != null && !value.isEmpty() ? value : fallback);
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
