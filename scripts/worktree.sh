#!/bin/bash
# worktree.sh - Helper script for git worktree operations
#
# Usage:
#   ./scripts/worktree.sh new feature/my-feature    # Create new feature worktree
#   ./scripts/worktree.sh list                       # List all worktrees
#   ./scripts/worktree.sh remove feature/my-feature # Remove a worktree
#   ./scripts/worktree.sh cd feature/my-feature     # Print cd command (use with: cd $(./scripts/worktree.sh cd feature/my-feature))

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKTREE_DIR="$(dirname "$REPO_ROOT")/matlabClaude-worktrees"

# Convert branch name to directory name (feature/voice-input -> feature-voice-input)
branch_to_dir() {
    echo "$1" | tr '/' '-'
}

# Convert directory name back to branch name (feature-voice-input -> feature/voice-input)
dir_to_branch() {
    local dir="$1"
    # Handle common prefixes
    for prefix in feature bugfix experiment refactor hotfix; do
        if [[ "$dir" == "${prefix}-"* ]]; then
            echo "${prefix}/${dir#${prefix}-}"
            return
        fi
    done
    echo "$dir"
}

case "${1:-help}" in
    new|create|add)
        if [ -z "$2" ]; then
            echo "Usage: $0 new <branch-name>"
            echo "Example: $0 new feature/voice-input"
            exit 1
        fi
        BRANCH="$2"
        DIR_NAME="$(branch_to_dir "$BRANCH")"
        WORKTREE_PATH="$WORKTREE_DIR/$DIR_NAME"

        echo "Creating worktree for branch '$BRANCH'..."
        git -C "$REPO_ROOT" fetch origin
        git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" -b "$BRANCH" origin/main

        echo ""
        echo "Worktree created at: $WORKTREE_PATH"
        echo "To start working:"
        echo "  cd $WORKTREE_PATH"
        ;;

    list|ls)
        git -C "$REPO_ROOT" worktree list
        ;;

    remove|rm|delete)
        if [ -z "$2" ]; then
            echo "Usage: $0 remove <branch-name>"
            echo "Example: $0 remove feature/voice-input"
            exit 1
        fi
        BRANCH="$2"
        DIR_NAME="$(branch_to_dir "$BRANCH")"
        WORKTREE_PATH="$WORKTREE_DIR/$DIR_NAME"

        if [ ! -d "$WORKTREE_PATH" ]; then
            echo "Worktree not found: $WORKTREE_PATH"
            exit 1
        fi

        echo "Removing worktree at: $WORKTREE_PATH"
        git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH"

        read -p "Also delete the branch '$BRANCH'? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git -C "$REPO_ROOT" branch -d "$BRANCH" 2>/dev/null || \
            git -C "$REPO_ROOT" branch -D "$BRANCH"
            echo "Branch deleted."
        fi
        ;;

    cd|path)
        if [ -z "$2" ]; then
            echo "Usage: $0 cd <branch-name>"
            echo "Example: cd \$($0 cd feature/voice-input)"
            exit 1
        fi
        BRANCH="$2"
        DIR_NAME="$(branch_to_dir "$BRANCH")"
        WORKTREE_PATH="$WORKTREE_DIR/$DIR_NAME"

        if [ -d "$WORKTREE_PATH" ]; then
            echo "$WORKTREE_PATH"
        else
            echo "Worktree not found: $WORKTREE_PATH" >&2
            exit 1
        fi
        ;;

    prune)
        echo "Pruning stale worktree references..."
        git -C "$REPO_ROOT" worktree prune -v
        ;;

    help|--help|-h|*)
        echo "Git Worktree Helper for matlabClaude"
        echo ""
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  new <branch>      Create a new worktree with a feature branch"
        echo "  list              List all worktrees"
        echo "  remove <branch>   Remove a worktree (optionally delete branch)"
        echo "  cd <branch>       Print the path to a worktree"
        echo "  prune             Clean up stale worktree references"
        echo "  help              Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 new feature/voice-input"
        echo "  $0 list"
        echo "  $0 remove feature/voice-input"
        echo "  cd \$($0 cd feature/voice-input)"
        ;;
esac
