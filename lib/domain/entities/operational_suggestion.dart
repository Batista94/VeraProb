import 'package:equatable/equatable.dart';

/// Semantic action type for an automated suggestion.
///
/// The presentation layer maps this to an icon and a callback — the domain
/// never knows about Flutter widgets or Riverpod.
enum SuggestionAction { cancelTrip, interruptTrip, regularizeTrip }

/// Represents an automated action recommendation from the Suggestion Engine.
///
/// Pure domain model — no Flutter, no callbacks, no icons.
/// The presentation layer (vehicle_detail_drawer) resolves [action] into
/// an [IconData] and a [VoidCallback] via [SuggestionActionUi].
class OperationalSuggestion extends Equatable {
  final String title;
  final String description;
  final String actionLabel;
  final SuggestionAction action;

  const OperationalSuggestion({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.action,
  });

  @override
  List<Object?> get props => [title, description, actionLabel, action];
}
