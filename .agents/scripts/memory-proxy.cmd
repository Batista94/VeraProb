@echo off
REM Memory Proxy for MCP - Enterprise Version
REM Using a Batch script avoids PowerShell's stdio corruption issues which break MCP JSON-RPC.

REM Resolve paths relative to this script
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%..\..\"
set "MEMORY_DIR=%PROJECT_ROOT%.agents\memory"
set "MEMORY_PATH=%MEMORY_DIR%\graph.db"

REM Ensure directory exists
if not exist "%MEMORY_DIR%" mkdir "%MEMORY_DIR%"

REM Run the MCP server via npx pointing to the centralized project database
npx.cmd -y @modelcontextprotocol/server-memory --memory-path "%MEMORY_PATH%"
