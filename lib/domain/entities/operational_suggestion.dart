import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Represents an automated action recommendation from the Suggestion Engine.
class OperationalSuggestion extends Equatable {
  final String title;
  final String description;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onExecute;

  const OperationalSuggestion({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.actionIcon,
    required this.onExecute,
  });

  @override
  List<Object?> get props => [title, description, actionLabel, actionIcon];
}
