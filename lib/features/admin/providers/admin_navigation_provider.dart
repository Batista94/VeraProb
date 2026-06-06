import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/admin/providers/onboarding_provider.dart';

/// Stable destination identity for the admin shell.
///
/// `.index` is the position inside the [AdminLayout] `IndexedStack`.
/// The first [pillarCount] entries are the visible sidebar pillars; the
/// remainder are reached through the Administração hub launcher.
///
/// NEVER address screens by integer literal — reference `AdminNav.x.index`
/// so reordering the shell stays atomic across sidebar, hub, onboarding
/// banner and the command-center drawer.
enum AdminNav {
  // ── Operational pillars (visible in the sidebar) ──────────
  dashboard,
  auditorQueue,
  defensePortal,
  financialImpact,
  operationalAudit,
  adminHub,
  // ── Hub destinations (reached via the launcher) ───────────
  drivers,
  timecards,
  contracts,
  slaAudit,
  zones,
  billingReports,
  slaTemplates,
  orgSettings,
  userManagement,
  contractors,
  settings,
  evidence,
}

/// Number of leading [AdminNav] entries rendered as sidebar pillars
/// (includes the Administração hub entry point).
const int pillarCount = 6;

/// Maps a real screen index to its sidebar rail position. Deep hub
/// screens (index >= [pillarCount]) collapse onto the Administração pillar.
int railIndexFor(int realIndex) =>
    realIndex < pillarCount ? realIndex : AdminNav.adminHub.index;

// State provider for the currently selected admin screen index.
class _AdminIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;

  void go(AdminNav destination) => state = destination.index;
}

final adminIndexProvider = NotifierProvider<_AdminIndexNotifier, int>(
  _AdminIndexNotifier.new,
);

class _OnboardingBannerVisibleNotifier extends Notifier<bool> {
  bool _isDismissed = false;

  @override
  bool build() {
    final progress = ref.watch(onboardingProgressProvider);
    if (progress.isComplete) {
      return false;
    }
    return !_isDismissed;
  }

  void toggle() {
    state = !state;
    if (!state) {
      _isDismissed = true;
    } else {
      _isDismissed = false;
    }
  }
}

final onboardingBannerVisibleProvider =
    NotifierProvider<_OnboardingBannerVisibleNotifier, bool>(
      _OnboardingBannerVisibleNotifier.new,
    );
