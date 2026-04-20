import 'package:equatable/equatable.dart';

class AuthorizationObligation extends Equatable {
  final String type;
  final Map<String, dynamic> metadata;

  const AuthorizationObligation({required this.type, this.metadata = const {}});

  Map<String, dynamic> toJson() {
    return {'type': type, 'metadata': metadata};
  }

  @override
  List<Object?> get props => [type, metadata];
}
