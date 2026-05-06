# Memory Proxy for MCP - Enterprise Version
# This script ensures that all AI tools (Antigravity, Claude Code, Kiro) 
# share the exact same memory graph regardless of where the project is located.

# Use $PSScriptRoot to resolve the path relative to this script's location,
# not relative to the CWD of the calling process (which varies per IDE).
$ScriptDir   = $PSScriptRoot                          # .agents\scripts\
$ProjectRoot = Split-Path (Split-Path $ScriptDir)    # .agents\ -> project root
$MemoryDir   = Join-Path $ProjectRoot ".agents\memory"
$MemoryPath  = Join-Path $MemoryDir "graph.db"

# Ensure memory directory exists
if (-not (Test-Path $MemoryDir)) {
    New-Item -ItemType Directory -Path $MemoryDir -Force | Out-Null
}

# Run the MCP server via npx pointing to the centralized project database
npx.cmd -y @modelcontextprotocol/server-memory --memory-path "$MemoryPath"
