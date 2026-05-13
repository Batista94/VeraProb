import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/tenant_status_filter.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ── Injectable debounce duration ─────────────────────────────────────────────

/// Override with `Duration.zero` in tests to bypass timer.
final tenantSearchDebounceDurationProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 300),
);

// ── Notifier ─────────────────────────────────────────────────────────────────

class TenantSearchNotifier
    extends Notifier<AsyncValue<List<TenantHealthView>>> {
  String _searchQuery = '';
  String _debouncedQuery = '';
  TenantStatusFilter _statusFilter = TenantStatusFilter.all;
  Timer? _debounceTimer;

  String get searchQuery => _searchQuery;
  TenantStatusFilter get statusFilter => _statusFilter;

  /// True while the debounce timer is active. UI uses this for shimmer overlay.
  bool get isDebouncing => _debounceTimer?.isActive ?? false;

  @override
  AsyncValue<List<TenantHealthView>> build() {
    ref.onDispose(_cancelTimer);
    final snapshot = ref.watch(tenantHealthSnapshotProvider);
    return snapshot.whenData(_applyFilters);
  }

  void setQuery(String query) {
    _searchQuery = query;
    _cancelTimer();

    final duration = ref.read(tenantSearchDebounceDurationProvider);
    if (duration == Duration.zero) {
      _debouncedQuery = query;
      _refilter();
      return;
    }

    _debounceTimer = Timer(duration, () {
      _debouncedQuery = _searchQuery;
      _refilter();
    });

    // Notify UI so it can read isDebouncing and show shimmer overlay.
    ref.notifyListeners();
  }

  void setStatusFilter(TenantStatusFilter filter) {
    _statusFilter = filter;
    _refilter();
  }

  void _refilter() {
    final tenantsAsync = ref.read(tenantHealthSnapshotProvider);
    if (tenantsAsync.hasValue) {
      state = AsyncData(_applyFilters(tenantsAsync.value!));
    }
  }

  List<TenantHealthView> _applyFilters(List<TenantHealthView> all) {
    var filtered = all;

    if (_statusFilter != TenantStatusFilter.all) {
      filtered = filtered
          .where((t) => _statusFilter.matches(isActive: t.isActive))
          .toList();
    }

    final trimmed = _debouncedQuery.trim();
    if (trimmed.isEmpty) return filtered;

    final normalizedQuery = normalizeText(trimmed);
    final digitsQuery = extractDigits(trimmed);

    return filtered.where((t) {
      return normalizeText(t.name).contains(normalizedQuery) ||
          (t.legalName != null &&
              normalizeText(t.legalName!).contains(normalizedQuery)) ||
          normalizeText(t.id).contains(normalizedQuery) ||
          (t.cnpj != null &&
              digitsQuery.isNotEmpty &&
              extractDigits(t.cnpj!).contains(digitsQuery));
    }).toList();
  }

  void _cancelTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}

final tenantSearchProvider =
    NotifierProvider<TenantSearchNotifier, AsyncValue<List<TenantHealthView>>>(
      TenantSearchNotifier.new,
    );

// ── Pure normalization functions (isolate-ready) ─────────────────────────────

@visibleForTesting
String normalizeText(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãäå]'), 'a')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[ñ]'), 'n');
}

@visibleForTesting
String extractDigits(String text) => text.replaceAll(RegExp(r'[^0-9]'), '');
