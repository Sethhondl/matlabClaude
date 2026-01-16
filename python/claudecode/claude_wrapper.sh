#!/bin/bash
# Wrapper script to run Claude CLI with proper environment
# This is needed because asyncio.subprocess_exec doesn't handle symlinks to scripts properly

# Find node in common locations
if [ -d "$HOME/.nvm/versions/node" ]; then
    # Use the most recent node version
    NODE_DIR=$(ls -d "$HOME/.nvm/versions/node/"* 2>/dev/null | sort -V | tail -1)
    if [ -n "$NODE_DIR" ]; then
        export PATH="$NODE_DIR/bin:$PATH"
    fi
fi

# Also check Homebrew
if [ -d "/usr/local/opt/node/bin" ]; then
    export PATH="/usr/local/opt/node/bin:$PATH"
fi
if [ -d "/opt/homebrew/opt/node/bin" ]; then
    export PATH="/opt/homebrew/opt/node/bin:$PATH"
fi

# Run claude with all arguments passed through
exec claude "$@"
