import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/shared/utils/cnpj_validator.dart';

void main() {
  group('CnpjValidator.isValid — Módulo 11 (CT-MOD11)', () {
    group('CNPJs estruturalmente válidos', () {
      test('45518855000147 passa', () {
        expect(CnpjValidator.isValid('45518855000147'), isTrue);
      });

      test('11222333000181 passa', () {
        expect(CnpjValidator.isValid('11222333000181'), isTrue);
      });
    });

    group('CNPJs inválidos — dígitos verificadores errados', () {
      test('12345678000100 falha (dígitos verificadores incorretos)', () {
        expect(CnpjValidator.isValid('12345678000100'), isFalse);
      });

      test('45518855000148 falha (último dígito incrementado)', () {
        expect(CnpjValidator.isValid('45518855000148'), isFalse);
      });

      test('45518855000157 falha (primeiro verificador errado)', () {
        expect(CnpjValidator.isValid('45518855000157'), isFalse);
      });
    });

    group('CNPJs inválidos — sequências repetidas', () {
      test('00000000000000 falha (todos zeros)', () {
        expect(CnpjValidator.isValid('00000000000000'), isFalse);
      });

      test('11111111111111 falha', () {
        expect(CnpjValidator.isValid('11111111111111'), isFalse);
      });

      test('99999999999999 falha', () {
        expect(CnpjValidator.isValid('99999999999999'), isFalse);
      });
    });

    group('CNPJs inválidos — comprimento incorreto', () {
      test('string vazia retorna false', () {
        expect(CnpjValidator.isValid(''), isFalse);
      });

      test('13 dígitos retorna false', () {
        expect(CnpjValidator.isValid('4551885500014'), isFalse);
      });

      test('15 dígitos retorna false', () {
        expect(CnpjValidator.isValid('455188550001477'), isFalse);
      });
    });
  });
}
