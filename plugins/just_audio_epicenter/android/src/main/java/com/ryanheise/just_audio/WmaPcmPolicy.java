package com.ryanheise.just_audio;

/** Container precision is not proof of the source's effective resolution. */
final class WmaPcmPolicy {
    static String codec(int sourceBits, String decodedFormat) {
        if (sourceBits > 0 && sourceBits <= 16) return "pcm_s16le";
        if (sourceBits > 16 && sourceBits <= 24) return "pcm_s24le";
        if (sourceBits > 24 && sourceBits <= 32) return "pcm_s32le";
        if ("s16".equals(decodedFormat) || "s16p".equals(decodedFormat)) return "pcm_s16le";
        if ("s32".equals(decodedFormat) || "s32p".equals(decodedFormat)) return "pcm_s32le";
        // Lossy WMA often decodes to float without a meaningful source bit depth.
        // Store that output directly, without an additional integer quantization.
        return "pcm_f32le";
    }
}
