package com.ryanheise.just_audio;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.Map;

public class MainMethodCallHandler implements MethodCallHandler {

    private final Context applicationContext;
    private final BinaryMessenger messenger;

    private final Map<String, AudioPlayer> players = new HashMap<>();
    private final Handler crossfadeHandler = new Handler(Looper.getMainLooper());
    private int crossfadeGeneration = 0;
    private Result pendingCrossfadeResult;

    public MainMethodCallHandler(Context applicationContext,
            BinaryMessenger messenger) {
        this.applicationContext = applicationContext;
        this.messenger = messenger;
    }

    @Override
    public void onMethodCall(MethodCall call, @NonNull Result result) {
        switch (call.method) {
        case "init": {
            String id = call.argument("id");
            if (players.containsKey(id)) {
                result.error("Platform player " + id + " already exists", null, null);
                break;
            }
            List<Object> rawAudioEffects = call.argument("androidAudioEffects");
            players.put(
                id,
                new AudioPlayer(
                    applicationContext,
                    messenger,
                    id,
                    call.argument("audioLoadConfiguration"),
                    rawAudioEffects,
                    call.argument("androidAudioOffloadPreferences"),
                    call.argument("androidOffloadSchedulingEnabled"),
		    call.argument("useLazyPreparation")
                )
            );
            result.success(null);
            break;
        }
        case "disposePlayer": {
            String id = call.argument("id");
            AudioPlayer player = players.get(id);
            if (player != null) {
                player.dispose();
                players.remove(id);
            }
            result.success(new HashMap<String, Object>());
            break;
        }
        case "disposeAllPlayers": {
            dispose();
            result.success(new HashMap<String, Object>());
            break;
        }
        case "crossfadePlayers": {
            String fromId = call.argument("fromId");
            String toId = call.argument("toId");
            Number durationValue = call.argument("durationMs");
            Number fromStartValue = call.argument("fromStartVolume");
            Number toEndValue = call.argument("toEndVolume");
            Number intensityValue = call.argument("effectIntensity");
            AudioPlayer from = players.get(fromId);
            AudioPlayer to = players.get(toId);
            if (from == null || to == null || durationValue == null) {
                result.error("INVALID_ARGUMENT", "Both active player IDs are required", null);
                break;
            }
            startCrossfade(
                from,
                to,
                Math.max(1L, durationValue.longValue()),
                fromStartValue == null ? 1.0f : fromStartValue.floatValue(),
                toEndValue == null ? 1.0f : toEndValue.floatValue(),
                (String)call.argument("curve"),
                (String)call.argument("effect"),
                intensityValue == null ? 0.65f : intensityValue.floatValue(),
                result
            );
            break;
        }
        case "cancelCrossfade": {
            cancelCrossfade();
            result.success(new HashMap<String, Object>());
            break;
        }
        default:
            result.notImplemented();
            break;
        }
    }

    private void startCrossfade(
            final AudioPlayer from,
            final AudioPlayer to,
            final long durationMs,
            final float fromStartVolume,
            final float toEndVolume,
            final String requestedCurve,
            final String requestedEffect,
            final float effectIntensity,
            final Result result) {
        cancelCrossfade();
        final int generation = ++crossfadeGeneration;
        final long startedAt = SystemClock.elapsedRealtime();
        final String curve = requestedCurve == null ? "equalPower" : requestedCurve;
        final String effect = requestedEffect == null ? "smooth" : requestedEffect;
        pendingCrossfadeResult = result;
        from.beginTransitionEffect(effect, "outgoing", effectIntensity);
        to.beginTransitionEffect(effect, "incoming", effectIntensity);

        crossfadeHandler.post(new Runnable() {
            @Override
            public void run() {
                if (generation != crossfadeGeneration) return;
                float progress = Math.min(
                    1.0f,
                    (SystemClock.elapsedRealtime() - startedAt) / (float)durationMs
                );
                float fromGain;
                float toGain;
                from.updateTransitionEffect(progress);
                to.updateTransitionEffect(progress);
                if ("quickCut".equals(curve)) {
                    fromGain = progress < 0.48f ? 1.0f : Math.max(0.0f, 1.0f - (progress - 0.48f) / 0.04f);
                    toGain = progress < 0.48f ? 0.0f : Math.min(1.0f, (progress - 0.48f) / 0.04f);
                } else {
                    fromGain = (float)Math.cos(progress * Math.PI * 0.5);
                    toGain = (float)Math.sin(progress * Math.PI * 0.5);
                }
                from.setVolume(fromStartVolume * fromGain);
                to.setVolume(toEndVolume * toGain);
                if (progress >= 1.0f) {
                    from.endTransitionEffect();
                    to.endTransitionEffect();
                    Result completed = pendingCrossfadeResult;
                    pendingCrossfadeResult = null;
                    if (completed != null) completed.success(new HashMap<String, Object>());
                } else {
                    crossfadeHandler.postDelayed(this, 12L);
                }
            }
        });
    }

    private void cancelCrossfade() {
        crossfadeGeneration++;
        crossfadeHandler.removeCallbacksAndMessages(null);
        for (AudioPlayer player : players.values()) {
            player.endTransitionEffect();
        }
        Result cancelled = pendingCrossfadeResult;
        pendingCrossfadeResult = null;
        if (cancelled != null) {
            cancelled.error("CANCELLED", "Crossfade cancelled", null);
        }
    }

    void dispose() {
        cancelCrossfade();
        for (AudioPlayer player : new ArrayList<AudioPlayer>(players.values())) {
            player.dispose();
        }
        players.clear();
    }
}
