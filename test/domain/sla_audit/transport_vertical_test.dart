import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';

void main() {
  group('TransportVertical', () {
    test('todos os valores têm label PT-BR não vazio', () {
      for (final vertical in TransportVertical.values) {
        expect(vertical.label, isNotEmpty);
      }
    });

    test('toJson retorna name do enum', () {
      expect(TransportVertical.fretamento.toJson(), 'fretamento');
      expect(TransportVertical.cargaSeca.toJson(), 'cargaSeca');
      expect(TransportVertical.escolar.toJson(), 'escolar');
    });

    test('fromJson round-trip para todos os valores', () {
      for (final vertical in TransportVertical.values) {
        final json = vertical.toJson();
        final restored = TransportVertical.fromJson(json);
        expect(restored, vertical);
      }
    });

    test('fromJson com valor desconhecido retorna custom', () {
      expect(
        TransportVertical.fromJson('inexistente'),
        TransportVertical.custom,
      );
    });

    test('fromJson com null retorna custom', () {
      expect(TransportVertical.fromJson(null), TransportVertical.custom);
    });

    test('labels esperados por vertical', () {
      expect(TransportVertical.fretamento.label, 'Fretamento');
      expect(TransportVertical.cargaSeca.label, 'Carga Seca');
      expect(TransportVertical.cargaRefrigerada.label, 'Carga Refrigerada');
      expect(
        TransportVertical.transferenciaFuncionarios.label,
        'Transferência de Funcionários',
      );
      expect(TransportVertical.escolar.label, 'Escolar');
      expect(TransportVertical.custom.label, 'Personalizado');
    });
  });
}
