#!/bin/bash
# mcp_client.sh - MCP Client Helper for Integration Tests
#
# Provides bash functions to interact with the MCP server via curl.

# Configuration
MCP_HOST="${MCP_HOST:-localhost}"
MCP_PORT="${MCP_PORT:-3000}"
MCP_SESSION_ID=""
REQUEST_ID=0

# JSON-RPC request helper
mcp_request() {
    local method="$1"
    local params="$2"

    ((REQUEST_ID++))

    local request
    if [ -z "$params" ] || [ "$params" == "{}" ]; then
        request="{\"jsonrpc\":\"2.0\",\"id\":$REQUEST_ID,\"method\":\"$method\",\"params\":{}}"
    else
        request="{\"jsonrpc\":\"2.0\",\"id\":$REQUEST_ID,\"method\":\"$method\",\"params\":$params}"
    fi

    local headers=()
    headers+=(-H "Content-Type: application/json")
    if [ -n "$MCP_SESSION_ID" ]; then
        headers+=(-H "Mcp-Session-Id: $MCP_SESSION_ID")
    fi

    local response
    response=$(curl -s -D - "${headers[@]}" \
        -d "$request" \
        "http://${MCP_HOST}:${MCP_PORT}/")

    # Extract session ID from headers
    local new_session
    new_session=$(echo "$response" | grep -i "Mcp-Session-Id:" | cut -d: -f2 | tr -d ' \r\n')
    if [ -n "$new_session" ]; then
        MCP_SESSION_ID="$new_session"
    fi

    # Return body only (after blank line)
    echo "$response" | sed -n '/^\r$/,${/^\r$/!p}'
}

# Initialize MCP session
mcp_initialize() {
    local client_name="${1:-test-client}"
    local client_version="${2:-1.0.0}"

    mcp_request "initialize" "{\"clientInfo\":{\"name\":\"$client_name\",\"version\":\"$client_version\"}}"
}

# List available tools
mcp_tools_list() {
    mcp_request "tools/list" "{}"
}

# Call a tool
mcp_tools_call() {
    local tool_name="$1"
    local arguments="$2"

    if [ -z "$arguments" ]; then
        arguments="{}"
    fi

    mcp_request "tools/call" "{\"name\":\"$tool_name\",\"arguments\":$arguments}"
}

# SSH Connect helper
mcp_ssh_connect() {
    local host="$1"
    local user="$2"
    local password="$3"
    local insecure="${4:-false}"

    mcp_tools_call "ssh_connect" "{\"host\":\"$host\",\"user\":\"$user\",\"password\":\"$password\",\"insecure\":$insecure}"
}

# SSH Run Command helper
mcp_ssh_run() {
    local session_id="$1"
    local command="$2"

    # Escape double quotes in command
    local escaped_cmd
    escaped_cmd=$(echo "$command" | sed 's/"/\\"/g')

    mcp_tools_call "ssh_run_command" "{\"session_id\":\"$session_id\",\"command\":\"$escaped_cmd\"}"
}

# SSH Cat File helper
mcp_ssh_cat_file() {
    local session_id="$1"
    local path="$2"

    mcp_tools_call "ssh_cat_file" "{\"session_id\":\"$session_id\",\"path\":\"$path\"}"
}

# SSH Disconnect helper
mcp_ssh_disconnect() {
    local session_id="$1"

    mcp_tools_call "ssh_disconnect" "{\"session_id\":\"$session_id\"}"
}

# SSH List Sessions helper
mcp_ssh_list_sessions() {
    mcp_tools_call "ssh_list_sessions" "{}"
}

# SSH Hostname helper
mcp_ssh_hostname() {
    local session_id="$1"

    mcp_tools_call "ssh_hostname" "{\"session_id\":\"$session_id\"}"
}

# Health check
mcp_health() {
    curl -s "http://${MCP_HOST}:${MCP_PORT}/health"
}

# Metrics
mcp_metrics() {
    curl -s "http://${MCP_HOST}:${MCP_PORT}/metrics"
}

# Extract session_id from response
extract_session_id() {
    local response="$1"
    echo "$response" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4
}

# Check if response contains error
has_error() {
    local response="$1"
    echo "$response" | grep -qi '"error"\|"isError"[[:space:]]*:[[:space:]]*true'
}

# Check if response contains specific text
contains_text() {
    local response="$1"
    local text="$2"
    echo "$response" | grep -qi "$text"
}
