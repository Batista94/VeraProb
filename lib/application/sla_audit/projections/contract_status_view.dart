/// Presentation-friendly representation of [ContractStatus].
///
/// This exists solely to satisfy the architectural requirement that the
/// Presentation Layer (`lib/features/`) never imports the Domain Layer directly.
enum ContractStatusView {
  draft,
  awaitingContractorAcceptance,
  active,
  closed;

  String get label => switch (this) {
    draft => 'RASCUNHO',
    awaitingContractorAcceptance => 'AGUARDANDO ACEITE',
    active => 'ATIVO',
    closed => 'ENCERRADO',
  };
}
