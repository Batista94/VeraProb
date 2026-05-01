#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: C:\Projects\VeraProb\.kiro\scripts\pre-tool-use.sh
# Objetivo: Bloquear tools caros/redundantes, economizando 40-60% tokens.
#
# Exemplos de Teste:
# 1. Block forbidden path:
#    KIRO_HOOK_JSON='{"tool_name":"read_file","tool_input":{"path":"node_modules/pkg/lib.js"}}' ./pre-tool-use.sh
# 2. Block long input:
#    KIRO_HOOK_JSON='{"tool_name":"run_command","tool_input":"...800+ chars..."}' ./pre-tool-use.sh
# 3. Block non-headless playwright:
#    KIRO_HOOK_JSON='{"tool_name":"playwright_browser_click","tool_input":{"headless":false}}' ./pre-tool-use.sh
# ==============================================================================

# Parse JSON input (MANDATÓRIO: $KIRO_HOOK_JSON deve estar no env)
TOOL_NAME=$(echo "$KIRO_HOOK_JSON" | jq -r '.tool_name')
TOOL_INPUT=$(echo "$KIRO_HOOK_JSON" | jq -r '.tool_input')

case "$TOOL_NAME" in
    *read*|*write*)
        # Bloqueia se path em .kiroignore OU .gitignore OU node_modules/build/dist
        FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.path // .AbsolutePath // .TargetFile // .SearchPath // empty' 2>/dev/null || echo "$TOOL_INPUT")
        
        # Normalize path for regex check (remove leading ./ if present)
        CLEAN_PATH="${FILE_PATH#./}"
        
        if [[ "$CLEAN_PATH" =~ ^(node_modules|build|dist)(/|$) ]] || \
           ( [ -f .kiroignore ] && grep -qxF "$FILE_PATH" .kiroignore ) || \
           git check-ignore -q "$FILE_PATH" 2>/dev/null; then
            echo "ERRO: Path '$FILE_PATH' bloqueado (.gitignore/.kiroignore/forbidden dir)." >&2
            exit 2
        fi
        ;;

    *playwright*|*docker*)
        # "playwright"/"docker": STDERR "Use MCP memory primeiro" + exit 2 se sem --headless ou container <1GB
        HEADLESS_MODE=$(echo "$TOOL_INPUT" | jq -r '.headless // empty' 2>/dev/null || echo "false")
        
        if [[ "$TOOL_INPUT" != *"--headless"* ]] && [[ "$HEADLESS_MODE" != "true" ]]; then
            echo "Use MCP memory primeiro" >&2
            exit 2
        fi

        # Check docker memory limit < 1GB
        if [[ "$TOOL_INPUT" =~ --memory[[:space:]=]*([0-9]+)([mMkKgG]) ]]; then
            VAL="${BASH_REMATCH[1]}"
            UNIT="${BASH_REMATCH[2]}"
            if [[ "$UNIT" =~ [mM] && "$VAL" -lt 1024 ]]; then
                echo "Use MCP memory primeiro" >&2
                exit 2
            fi
        fi
        ;;

    *fetch*|*web*|*shell*|*run_command*)
        # Bloqueia se ${#TOOL_INPUT} >800 chars: "Prompt muito longo, use MCP"
        if [ "${#TOOL_INPUT}" -gt 800 ]; then
            echo "Prompt muito longo, use MCP" >&2
            exit 2
        fi
        ;;

    *github*|*postgres*)
        # Log "Desabilitado no config"
        echo "Desabilitado no config" >&2
        exit 2
        ;;
esac

exit 0
