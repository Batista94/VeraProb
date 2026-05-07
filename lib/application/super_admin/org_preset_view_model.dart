import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/domain/super_admin/org_vertical_preset.dart';

/// Application-layer ViewModel that surfaces preset metadata for the UI.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// - The UI accesses preset labels and resolved capabilities only through this
///   class. [OrgVerticalPreset] (domain) is never imported in `lib/features/`.
/// - [resolveCapabilities] converts the domain-level preset constants into
///   [OrgCapabilitiesViewModel] so the widget never handles [OrgCapabilities]
///   directly.
abstract final class OrgPresetViewModel {
  /// Human-readable labels keyed by preset identifier.
  ///
  /// Presentation code uses this map to populate selector widgets.
  /// Values are stable UI strings; keys are opaque identifiers passed back
  /// to [resolveCapabilities].
  static Map<String, String> get labels => OrgVerticalPreset.labels;

  /// Resolves the [OrgCapabilitiesViewModel] for a given [presetKey].
  ///
  /// Returns [OrgCapabilitiesViewModel.defaults] when [presetKey] is `null`
  /// (i.e. no preset selected) or when the key is not found — matching the
  /// behaviour previously performed inline in the wizard state.
  static OrgCapabilitiesViewModel resolveCapabilities(String? presetKey) {
    if (presetKey == null) return OrgCapabilitiesViewModel.defaults;
    final domainCaps = OrgVerticalPreset.defaults[presetKey];
    if (domainCaps == null) return OrgCapabilitiesViewModel.defaults;
    return OrgCapabilitiesViewModel.fromDomain(domainCaps);
  }
}
