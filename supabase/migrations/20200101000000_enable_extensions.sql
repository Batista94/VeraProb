-- Supabase pre-installs these extensions; suppress duplicate NOTICEs.
SET client_min_messages TO 'WARNING';

-- Habilita a extensão para geração de UUIDs v4
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

-- Se você usa o pgcrypto para outras funções:
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
