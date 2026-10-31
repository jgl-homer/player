import 'package:flutter/foundation.dart';

import 'lyrics_cache_repository.dart';
import 'lyrics_models.dart';
import 'lyrics_provider.dart';

class LyricsResolver {
  final LyricsCacheRepository cache;
  final Duration failureTtl;
  final Duration plainUpgradeTtl;
  final Map<String, Future<LyricsResult?>> _inFlight = {};

  LyricsResolver(
    this.cache, {
    this.failureTtl = const Duration(minutes: 30),
    this.plainUpgradeTtl = const Duration(days: 1),
  });

  Future<LyricsResult?> resolve(
    LyricsRequest request, {
    required String namespace,
    required List<LyricsProvider> providers,
    bool allowNetwork = true,
    bool forceRefresh = false,
  }) {
    final key = LyricsMetadata.cacheKey(request, namespace);
    final active = _inFlight[key];
    if (active != null) return active;
    final future = _resolve(
      key,
      request,
      providers,
      allowNetwork: allowNetwork,
      forceRefresh: forceRefresh,
    );
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<LyricsResult?> _resolve(
    String key,
    LyricsRequest request,
    List<LyricsProvider> providers, {
    required bool allowNetwork,
    required bool forceRefresh,
  }) async {
    final upgradeKey = 'timed-upgrade:$key';
    LyricsResult? plainFallback;
    var cachedPlain = false;
    if (!forceRefresh) {
      final cached = await cache.read(key);
      if (cached != null) {
        if (cached.hasTimestamps ||
            cached.synchronization != LyricsSynchronization.none ||
            !allowNetwork ||
            await cache.hasRecentFailure(upgradeKey, plainUpgradeTtl)) {
          return cached;
        }
        plainFallback = cached;
        cachedPlain = true;
      }
      if (await cache.hasRecentFailure(key, failureTtl)) return null;
    } else {
      await cache.remove(key);
      await cache.remove(upgradeKey);
    }

    final pending = <int, Future<_ProviderOutcome>>{};
    for (var index = 0; index < providers.length; index++) {
      final provider = providers[index];
      if (provider.requiresNetwork && !allowNetwork) continue;
      pending[index] = _fetchProvider(index, provider, request);
    }
    final attemptedProvider = pending.isNotEmpty;

    // Providers run together so a miss or timeout in one service cannot hold
    // the next song behind it. The first synchronized result wins; plain text
    // is retained only as a fallback after every provider has answered.
    while (pending.isNotEmpty) {
      final outcome = await Future.any(pending.values);
      pending.remove(outcome.index);
      if (outcome.error != null) {
        debugPrint('[Lyrics] ${outcome.providerId} falló: ${outcome.error}');
        continue;
      }
      final result = outcome.result;
      if (result == null) continue;
      final timestamped = result.copyWith(
        fetchedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      if (timestamped.hasTimestamps ||
          timestamped.synchronization != LyricsSynchronization.none) {
        await cache.write(key, request, timestamped);
        await cache.remove(upgradeKey);
        return timestamped;
      }
      plainFallback ??= timestamped;
    }
    if (plainFallback != null) {
      if (!cachedPlain) {
        await cache.write(key, request, plainFallback);
      }
      if (allowNetwork && attemptedProvider) {
        await cache.recordFailure(
          upgradeKey,
          reason: 'no_timed_lyrics_available',
        );
      }
      return plainFallback;
    }
    if (attemptedProvider) {
      await cache.recordFailure(key, reason: 'not_found_or_provider_error');
    }
    return null;
  }

  Future<void> invalidate(LyricsRequest request, String namespace) =>
      cache.remove(LyricsMetadata.cacheKey(request, namespace));

  Future<_ProviderOutcome> _fetchProvider(
    int index,
    LyricsProvider provider,
    LyricsRequest request,
  ) async {
    try {
      return _ProviderOutcome(
        index: index,
        providerId: provider.id,
        result: await provider.fetch(request),
      );
    } catch (error) {
      return _ProviderOutcome(
        index: index,
        providerId: provider.id,
        error: error,
      );
    }
  }
}

class _ProviderOutcome {
  final int index;
  final String providerId;
  final LyricsResult? result;
  final Object? error;

  const _ProviderOutcome({
    required this.index,
    required this.providerId,
    this.result,
    this.error,
  });
}
