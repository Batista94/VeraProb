// pr_scanner: ignore-regression
import 'package:veraprob/domain/reporting/forensic_dossier.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Exception thrown when the Executive-Grade PDF Certificate cannot be generated.
class PdfGenerationException extends DomainException {
  const PdfGenerationException(super.message);
}

/// Port for the application service to request PDF generation.
/// The implementation will use package:pdf to draw the layout.
abstract class IForensicPdfGenerator {
  /// Generates the PDF bytes for the given [ForensicDossier].
  /// The generated PDF MUST include the computed SHA-256 hash (INV-9)
  /// visibly in its footer.
  /// Throws [PdfGenerationException] if generation fails.
  Future<List<int>> generateDossier(ForensicDossier dossier);
}
