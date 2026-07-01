// WebhookSecretRevealResult — Application layer DTO (INV-13).
//
// Primitivos apenas. Nenhum tipo de infra ou domínio aqui.
// Retornado pela edge fn reveal-webhook-signing-secret e repassado
// ao RevealSecretModal via webhookSecretRevealProvider.
//
// INV-31: secretHex são os bytes derivados recomputados em runtime.
// O DB guarda APENAS version + status (webhook_signing_keys). Nenhum
// material de chave persiste em storage.

class WebhookSecretRevealResult {
  final String secretHex;
  final int version;

  const WebhookSecretRevealResult({
    required this.secretHex,
    required this.version,
  });
}
