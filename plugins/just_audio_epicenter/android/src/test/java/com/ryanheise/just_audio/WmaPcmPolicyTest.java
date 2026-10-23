package com.ryanheise.just_audio;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class WmaPcmPolicyTest {
    @Test public void preservesKnownSourcePrecision() {
        assertEquals("pcm_s16le", WmaPcmPolicy.codec(16, "fltp"));
        assertEquals("pcm_s24le", WmaPcmPolicy.codec(24, "s32p"));
        assertEquals("pcm_s32le", WmaPcmPolicy.codec(32, "s32"));
    }
    @Test public void unknownDepthPreservesDecoderRepresentation() {
        assertEquals("pcm_f32le", WmaPcmPolicy.codec(0, "fltp"));
        assertEquals("pcm_s16le", WmaPcmPolicy.codec(0, "s16p"));
        assertEquals("pcm_s32le", WmaPcmPolicy.codec(0, "s32p"));
        assertEquals("pcm_f32le", WmaPcmPolicy.codec(0, ""));
    }
}
