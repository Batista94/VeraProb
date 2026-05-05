# Memory Proxy for MCP - Enterprise Version
# This script ensures that all AI tools (Antigravity, Claude Code, Kiro) 
# share the exact same memory graph regardless of where the project is located.

$ProjectRoot = Get-Location
$MemoryPath = Join-Path $ProjectRoot ".agents\memory\graph.db"

# Ensure memory directory exists
if (-not (Test-Path ".agents\memory")) {
    New-Item -ItemType Directory -Path ".agents\memory" -Force | Out-Null
}

# Run the MCP server via npx
# We use --memory-path to point to our centralized project database
npx -y @modelcontextprotocol/server-memory --memory-path "$MemoryPath"
