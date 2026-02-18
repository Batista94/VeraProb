# BusFlow MVP 🚌

**Sistema de Monitoramento de Transporte Público em Tempo Real.**

Este projeto é um MVP (Minimum Viable Product) construído com **Flutter** (Web & Mobile) e **Supabase**, demonstrando uma arquitetura escalável para gestão de frotas e experiência do passageiro.

## 🚀 Arquitetura

O projeto utiliza **Clean Architecture** e é estruturado como um Monorepo com 3 pontos de entrada (Flavors):

*   **Passageiro** (`lib/main_passenger.dart`): App público para visualizar ônibus no mapa em tempo real.
*   **Motorista** (`lib/main_driver.dart`): App restrito para tracking GPS e controle de jornada.
*   **Admin Dashboard** (`lib/main_admin.dart`): Painel Web para gestão de frota e relatórios.

### Stack Tecnológico
*   **Frontend**: Flutter (Mobile + Web)
*   **Estado**: Riverpod
*   **Mapas**: `flutter_map` (OpenStreetMap)
*   **Backend/Realtime**: Supabase (PostgreSQL + PostGIS)
*   **Testes**: Mocktail, FakeAsync

---

## 🛠️ Como Executar (Localmente)

### 1. Pré-requisitos
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado.
*   Editor configurado (VS Code ou Android Studio).

### 2. Instalação
Clone o repositório e baixe as dependências:

```bash
git clone https://github.com/Batista94/Busflow.git
cd BusFlow
flutter pub get
```

### 3. Configuração de Variáveis (Supabase)
O projeto usa variáveis de ambiente para segurança (OWASP A02). Para rodar localmente com mocks ou seu próprio Supabase:

 **Opção A (Mocks/Default):**
Rode sem argumentos. O app usará valores padrão (inseguros/placeholders) que funcionam para testes de interface.

 **Opção B (Conexão Real):**
Passe as chaves na execução:
```bash
--dart-define=SUPABASE_URL=SUA_URL --dart-define=SUPABASE_KEY=SUA_ANON_KEY
```

---

## 📱 Comandos de Execução

Para rodar cada parte do sistema, use os comandos abaixo no terminal:

### 🖥️ Painel Admin (Web)
Use o Chrome para melhor experiência de desenvolvimento.
```bash
flutter run -d chrome -t lib/main_admin.dart --web-port 8080
```
*Acesse `http://localhost:8080` (PIN Padrão: `1234`)*

### 🚌 App Motorista (Mobile)
Rode em um emulador Android/iOS ou dispositivo físico.
```bash
flutter run -t lib/main_driver.dart
```

### 🧑‍🤝‍🧑 App Passageiro (Mobile)
Rode em um segundo emulador para testar a integração em tempo real.
```bash
flutter run -t lib/main_passenger.dart
```

---

## 🧪 Testes

### Automatizados
O projeto possui >88% de cobertura de testes na camada Web Admin.
```bash
flutter test
```

### Manuais
Veja o arquivo [walkthrough.md](walkthrough.md) para um roteiro detalhado de testes manuais e cenários de borda.

---

## 🔒 Segurança (OWASP Top 10)
O projeto segue práticas de segurança como:
*   Bloqueio por PIN no Admin (A07).
*   Logs centralizados (A09).
*   Segredos via Env Vars (A02).
*   Políticas RLS geradas para o banco de dados (A01).

---

Status: **Concluído (MVP)** ✅
