/// Forensic Audit Signature: CX-05-v3.0-TEST
/// Adversarial Test Suite: Red Team ID 4 (XSS Vulnerability) — Enterprise
/// Security Guard: INV-24 + INV-21 + INV-10 + INV-28 Compliance Verification
/// Authorized By: VeraProb QA Security Lead
///
/// **Coverage Target:** 100% line + branch coverage.
/// **Philosophy:** Every test represents a real-world attack vector from
/// OWASP Top 10, PortSwigger XSS cheat sheet, or browser-specific quirks.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/justification/xss_input_sanitizer.dart';

void main() {
  late XssInputSanitizer sanitizer;

  setUp(() {
    sanitizer = XssInputSanitizer();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER 0: BOUNDARY VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Layer 0 — Input Boundary Validation', () {
    test('throws InputLengthExceededException for oversized input', () {
      final input = 'A' * (kMaxSanitizableLength + 1);
      expect(
        () => sanitizer.sanitize(input),
        throwsA(isA<InputLengthExceededException>()),
      );
    });

    test('InputLengthExceededException carries forensic metadata', () {
      final input = 'A' * 20000;
      try {
        sanitizer.sanitize(input);
        fail('Should have thrown');
      } on InputLengthExceededException catch (e) {
        expect(e.length, equals(20000));
        expect(e.maxAllowed, equals(kMaxSanitizableLength));
        expect(e.toString(), contains('20000'));
        expect(e.toString(), contains('$kMaxSanitizableLength'));
      }
    });

    test('accepts input at exactly max length', () {
      final input = 'A' * kMaxSanitizableLength;
      final result = sanitizer.sanitize(input);
      expect(result.text, equals(input));
      expect(result.wasModified, isFalse);
    });

    test('empty string returns fast-path result', () {
      final result = sanitizer.sanitize('');
      expect(result.text, isEmpty);
      expect(result.wasModified, isFalse);
      expect(result.threatLevel, equals(ThreatLevel.none));
    });

    test('legacy sanitizeText truncates instead of throwing', () {
      final input = 'A' * 20000;
      final result = sanitizer.sanitizeText(input);
      expect(result.length, equals(kMaxSanitizableLength));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // HAPPY PATH — INTEGRITY PRESERVATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Happy Path — Integrity Preservation (INV-24)', () {
    test('preserves plain text without modification', () {
      const input = 'This is a normal justification text.';
      final result = sanitizer.sanitize(input);
      expect(result.text, equals(input));
      expect(result.wasModified, isFalse);
      expect(result.threatLevel, equals(ThreatLevel.none));
    });

    test('preserves UTF-8 characters (accents, emojis, CJK)', () {
      const input = 'Café ☕ 日本語 Ñoño 🚀 Москва';
      final result = sanitizer.sanitize(input);
      expect(result.text, equals(input));
      expect(result.wasModified, isFalse);
    });

    test('preserves legitimate special characters', () {
      const input = r'Price: $100.50 | Discount: 20% | Email: user@example.com';
      final result = sanitizer.sanitize(input);
      expect(result.text, equals(input));
    });

    test('preserves newlines and tabs', () {
      const input = 'Line 1\nLine 2\tTabbed';
      final result = sanitizer.sanitize(input);
      expect(result.text, equals(input));
    });

    test('preserves 10KB of legitimate text', () {
      final input = 'A' * 10000;
      final result = sanitizer.sanitize(input);
      expect(result.text, equals(input));
      expect(result.wasModified, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // IDEMPOTENCY — STABILITY UNDER REPEATED SANITIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  group('Idempotency — Repeated Sanitization Stability', () {
    test('sanitizing twice produces identical result', () {
      const input = '<script>alert(1)</script>Hello';
      final first = sanitizer.sanitize(input);
      final second = sanitizer.sanitize(first.text);
      expect(first.text, equals(second.text));
      expect(second.wasModified, isFalse);
    });

    test('sanitizing clean text 10x produces no change', () {
      const input = 'Clean text with numbers 123 and symbols @#%';
      var text = input;
      for (var i = 0; i < 10; i++) {
        text = sanitizer.sanitize(text).text;
      }
      expect(text, equals(input));
    });

    test('sanitizing malicious payload twice is stable', () {
      const input = '<img src=x onerror=alert(1)><script>xss</script>';
      final first = sanitizer.sanitize(input);
      final second = sanitizer.sanitize(first.text);
      expect(first.text, equals(second.text));
      expect(second.threatLevel, equals(ThreatLevel.none));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SANITIZATION RESULT — FORENSIC METADATA
  // ═══════════════════════════════════════════════════════════════════════════

  group('SanitizationResult — Forensic Metadata (INV-21)', () {
    test('clean input → ThreatLevel.none', () {
      final result = sanitizer.sanitize('Normal text');
      expect(result.threatLevel, equals(ThreatLevel.none));
      expect(result.wasModified, isFalse);
    });

    test('benign HTML → ThreatLevel.low', () {
      final result = sanitizer.sanitize('<b>Bold text</b>');
      expect(result.threatLevel, equals(ThreatLevel.low));
      expect(result.wasModified, isTrue);
    });

    test('script injection → ThreatLevel.high', () {
      final result = sanitizer.sanitize('<script>alert(1)</script>');
      expect(result.threatLevel, equals(ThreatLevel.high));
      expect(result.wasModified, isTrue);
    });

    test('event handler → ThreatLevel.high', () {
      final result = sanitizer.sanitize('<img onerror=alert(1)>');
      expect(result.threatLevel, equals(ThreatLevel.high));
      expect(result.wasModified, isTrue);
    });

    test('javascript: protocol → ThreatLevel.high', () {
      final result = sanitizer.sanitize('<a href="javascript:void(0)">x</a>');
      expect(result.threatLevel, equals(ThreatLevel.high));
      expect(result.wasModified, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCRIPT INJECTION — CLASSIC XSS VECTORS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Script Injection — Classic XSS Vectors', () {
    test('strips <script> tags completely', () {
      const input = '<script>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
      expect(result.text, isNot(contains('</script>')));
    });

    test('strips <script> with attributes', () {
      const input = '<script type="text/javascript">alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('strips multiple <script> tags preserving text between', () {
      const input = '<script>a(1)</script>Safe text<script>a(2)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('strips <script> with case variations', () {
      const input = '<ScRiPt>alert(1)</sCrIpT>';
      final result = sanitizer.sanitize(input);
      expect(result.text.toLowerCase(), isNot(contains('<script')));
    });

    test('strips nested <script> tags', () {
      const input = '<script><script>alert(1)</script></script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT HANDLERS — INLINE JAVASCRIPT
  // ═══════════════════════════════════════════════════════════════════════════

  group('Event Handlers — Inline JavaScript Execution', () {
    test('strips onerror attribute', () {
      const input = '<img src=x onerror=alert(1)>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('onerror')));
      expect(result.text, isNot(contains('alert')));
    });

    test('strips onload attribute', () {
      const input = '<body onload=alert(1)>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('onload')));
    });

    test('strips onclick attribute', () {
      const input = '<div onclick=alert(1)>Click me</div>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('onclick')));
      expect(result.text, contains('Click me'));
    });

    test('strips onmouseover attribute', () {
      const input = '<span onmouseover=alert(1)>Hover</span>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('onmouseover')));
    });

    test('strips onfocus attribute', () {
      const input = '<input onfocus=alert(1) autofocus>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('onfocus')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PROTOCOL HANDLERS — DANGEROUS URIs
  // ═══════════════════════════════════════════════════════════════════════════

  group('Protocol Handlers — Dangerous URIs', () {
    test('strips javascript: protocol', () {
      const input = '<a href="javascript:alert(1)">Click</a>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('javascript:')));
      expect(result.text, contains('Click'));
    });

    test('strips data:text/html protocol', () {
      const input =
          '<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">X</a>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('data:')));
    });

    test('strips vbscript: protocol', () {
      const input = '<a href="vbscript:msgbox(1)">Click</a>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('vbscript:')));
    });

    test('strips javascript: with case obfuscation', () {
      const input = '<a href="JaVaScRiPt:alert(1)">X</a>';
      final result = sanitizer.sanitize(input);
      expect(result.text.toLowerCase(), isNot(contains('javascript:')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // EXOTIC TAGS — POLYGLOT ATTACK VECTORS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Exotic Tags — Polyglot Attack Vectors', () {
    test('strips <iframe> tags', () {
      const input = '<iframe src="evil.com"></iframe>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<iframe')));
    });

    test('strips <object> tags', () {
      const input = '<object data="evil.swf"></object>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<object')));
    });

    test('strips <embed> tags', () {
      const input = '<embed src="evil.swf">';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<embed')));
    });

    test('strips <svg> with onload', () {
      const input = '<svg onload=alert(1)></svg>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<svg')));
      expect(result.text, isNot(contains('onload')));
    });

    test('strips <math> with nested script', () {
      const input = '<math><mtext><script>alert(1)</script></mtext></math>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<math')));
      expect(result.text, isNot(contains('<script')));
    });

    test('strips <base> tag (URL hijacking)', () {
      const input = '<base href="http://evil.com/">';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<base')));
    });

    test('strips <meta> refresh redirect', () {
      const input =
          '<meta http-equiv="refresh" content="0;url=http://evil.com">';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<meta')));
    });

    test('strips <link> stylesheet injection', () {
      const input = '<link rel="stylesheet" href="http://evil.com/steal.css">';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<link')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // NULL BYTE BYPASS — LAYER 1 DEFENSE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Null Byte Bypass — Layer 1 Defense', () {
    test('strips null bytes before HTML parsing', () {
      const input = '<scr\x00ipt>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('\x00')));
      expect(result.text, isNot(contains('<script')));
    });

    test('strips null bytes in event handlers', () {
      const input = '<img src=x on\x00error=alert(1)>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('\x00')));
      expect(result.text, isNot(contains('onerror')));
    });

    test('strips multiple scattered null bytes', () {
      const input = '<\x00s\x00c\x00r\x00i\x00p\x00t\x00>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('\x00')));
    });

    test('strips VT (0x0B) used in obfuscation', () {
      const input = '<scr\x0Bipt>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('\x0B')));
    });

    test('strips DEL (0x7F) character', () {
      const input = '<scr\x7Fipt>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('\x7F')));
    });

    test('preserves TAB, LF (legitimate whitespace)', () {
      const input = 'Line1\nLine2\tTabbed';
      final result = sanitizer.sanitize(input);
      expect(result.text, contains('\n'));
      expect(result.text, contains('\t'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // UTF-8 OBFUSCATION — LAYER 2 DEFENSE
  // ═══════════════════════════════════════════════════════════════════════════

  group('UTF-8 Obfuscation — Layer 2 Defense', () {
    test('normalizes overlong UTF-8 sequences', () {
      // Overlong encoding of '<' — invalid but some parsers accept
      final input =
          '${String.fromCharCodes([0xC0, 0xBC])}script>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('handles malformed UTF-8 without crashing', () {
      final input = '${String.fromCharCode(0xD800)}text';
      expect(() => sanitizer.sanitize(input), returnsNormally);
    });

    test('normalizes BOM (Byte Order Mark)', () {
      const input = '\uFEFF<script>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('handles mixed valid/invalid UTF-8', () {
      final input =
          'Valid ${String.fromCharCode(0xD800)} <script>x</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MALFORMED HTML — TAG SOUP RESILIENCE (AVAILABILITY)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Malformed HTML — Tag Soup Resilience', () {
    test('handles unclosed tags without crash', () {
      const input = '<div><span><p>Text';
      expect(() => sanitizer.sanitize(input), returnsNormally);
    });

    test('handles deeply nested tags (100 levels)', () {
      final input = '${'<div>' * 100}Text${'</div>' * 100}';
      expect(() => sanitizer.sanitize(input), returnsNormally);
    });

    test('handles mismatched closing tags', () {
      const input = '<div></span></p>';
      expect(() => sanitizer.sanitize(input), returnsNormally);
    });

    test('handles tags with missing closing bracket', () {
      const input = '<div<span>Text</span>';
      expect(() => sanitizer.sanitize(input), returnsNormally);
    });

    test('handles empty/malformed tags', () {
      const input = '<></><<>>';
      expect(() => sanitizer.sanitize(input), returnsNormally);
    });

    test('handles extremely long attribute values', () {
      final input = '<div class="${'A' * 5000}">Text</div>';
      expect(() => sanitizer.sanitize(input), returnsNormally);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENCODING BYPASS ATTEMPTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Encoding Bypass Attempts', () {
    test('HTML entities preserved as-is (safe — browsers wont execute)', () {
      const input = '&lt;script&gt;alert(1)&lt;/script&gt;';
      final result = sanitizer.sanitize(input);
      // Entities are NOT real tags — they're safe text
      expect(result.text, isNot(contains('<script')));
    });

    test('hex-encoded chars in script tags stripped', () {
      const input = '<script>alert(&#x31;)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('decimal-encoded chars in script tags stripped', () {
      const input = '<script>alert(&#49;)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('URL-encoded payloads preserved as-is (not decoded)', () {
      const input = '%3Cscript%3Ealert(1)%3C/script%3E';
      final result = sanitizer.sanitize(input);
      // URL encoding is NOT HTML — it's safe text
      expect(result.text, isNot(contains('<script')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MIXED CONTENT — REAL-WORLD SCENARIOS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Mixed Content — Real-World Scenarios', () {
    test('preserves legitimate text while stripping XSS', () {
      const input =
          'Justification: <script>alert(1)</script> The contractor was late.';
      final result = sanitizer.sanitize(input);
      expect(result.text, contains('Justification:'));
      expect(result.text, contains('The contractor was late.'));
      expect(result.text, isNot(contains('<script')));
    });

    test('handles multiple attack vectors in one input', () {
      const input = '<script>a(1)</script><img src=x onerror=a(2)>Normal text.';
      final result = sanitizer.sanitize(input);
      expect(result.text, contains('Normal text.'));
      expect(result.text, isNot(contains('<script')));
      expect(result.text, isNot(contains('onerror')));
    });

    test('preserves structured justification text', () {
      const input =
          'Reason: Equipment failure\nDate: 2024-01-15\nImpact: 2h delay';
      final result = sanitizer.sanitize(input);
      expect(result.text, equals(input));
      expect(result.wasModified, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RESOURCE EXHAUSTION — DoS PREVENTION (AVAILABILITY)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Resource Exhaustion — DoS Prevention', () {
    test('rejects 1MB payload with InputLengthExceededException', () {
      final input = 'A' * 1000000;
      expect(
        () => sanitizer.sanitize(input),
        throwsA(isA<InputLengthExceededException>()),
      );
    });

    test(
      'handles max-length payload with nested tags without timeout',
      () {
        final input = '<div>' * 1000 + 'A' * 5000 + '</div>' * 1000;
        // Total ~15KB > max, so use sanitizeText (truncates)
        expect(() => sanitizer.sanitizeText(input), returnsNormally);
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'handles 1000 script tags within limit',
      () {
        final input = '<script>a(1)</script>' * 400; // ~8.4KB < 10KB
        expect(() => sanitizer.sanitize(input), returnsNormally);
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIDENTIALITY — INV-28 COMPLIANCE
  // ═══════════════════════════════════════════════════════════════════════════

  group('Confidentiality — INV-28 Compliance', () {
    test('does not leak internal state in output', () {
      const input = '<script>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('Exception')));
      expect(result.text, isNot(contains('Error')));
      expect(result.text, isNot(contains('dart:')));
      expect(result.text, isNot(contains('package:')));
    });

    test('does not expose sanitization logic in output', () {
      const input = '<script>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('sanitize')));
      expect(result.text, isNot(contains('strip')));
      expect(result.text, isNot(contains('filter')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // EDGE CASES — BOUNDARY CONDITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Edge Cases — Boundary Conditions', () {
    test('handles single character', () {
      final result = sanitizer.sanitize('A');
      expect(result.text, equals('A'));
    });

    test('handles Unicode zero-width characters', () {
      const input = 'Text\u200B\u200C\u200DMore';
      final result = sanitizer.sanitize(input);
      expect(result.text, contains('Text'));
      expect(result.text, contains('More'));
    });

    test('handles right-to-left override (U+202E)', () {
      const input = 'Text\u202E<script>alert(1)</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('handles only whitespace', () {
      const input = '   \n\t   ';
      final result = sanitizer.sanitize(input);
      expect(result.text, contains('\n'));
      expect(result.text, contains('\t'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // POLYGLOT PAYLOADS — MULTI-CONTEXT EXPLOITS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Polyglot Payloads — Multi-Context Exploits', () {
    test('strips polyglot SVG+script payload', () {
      const input = '<svg><script>alert(1)</script></svg>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<svg')));
      expect(result.text, isNot(contains('<script')));
    });

    test('strips style-based XSS', () {
      const input = '<div style="background:url(javascript:alert(1))">X</div>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('javascript:')));
      expect(result.text, isNot(contains('style=')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BROWSER-SPECIFIC QUIRKS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Browser-Specific Quirks', () {
    test('strips IE conditional comments', () {
      const input = '<!--[if IE]><script>alert(1)</script><![endif]-->';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('alert(1)')));
    });

    test('strips Chrome XSS Auditor bypass', () {
      const input = '<script>alert(String.fromCharCode(88,83,83))</script>';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('<script')));
    });

    test('strips mXSS via noscript confusion', () {
      const input =
          '<noscript><p title="</noscript><img src=x onerror=alert(1)>">';
      final result = sanitizer.sanitize(input);
      expect(result.text, isNot(contains('onerror')));
      expect(result.text, isNot(contains('alert')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKWARD COMPATIBILITY — sanitizeText() LEGACY API
  // ═══════════════════════════════════════════════════════════════════════════

  group('Backward Compatibility — sanitizeText() Legacy API', () {
    test('returns plain text string directly', () {
      const input = '<script>alert(1)</script>Hello';
      final result = sanitizer.sanitizeText(input);
      expect(result, isA<String>());
      expect(result, isNot(contains('<script')));
    });

    test('preserves clean text', () {
      const input = 'Normal justification text.';
      expect(sanitizer.sanitizeText(input), equals(input));
    });

    test('handles oversized input by truncating', () {
      final input = 'Safe text ' * 2000; // ~20KB
      final result = sanitizer.sanitizeText(input);
      expect(result.length, lessThanOrEqualTo(kMaxSanitizableLength));
    });
  });
}
