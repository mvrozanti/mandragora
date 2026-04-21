# Mandragora Workflow: The Sync Ritual

This document defines how system logic (Nix) and state (Data) are synchronized between the Desktop, Notebook, and Slave.

## 1. System Logic (The Flake)
**Source of Truth:** Private Git Repository on Oracle VPS.

### The "Rebuild" Ritual
To prevent "Split Brain" scenarios, the `mandragora-switch` alias will perform:
1.  **`git fetch`**: Check for remote changes on the VPS.
2.  **`git status`**: If local and remote have diverged, the AI Agent assists in a `git rebase`.
3.  **`nixos-rebuild switch`**: Only executes if the local tree is clean and synced.
4.  **`git push`**: Automatically push successful changes back to the VPS.

## 2. User Data (The Content)
**Source of Truth:** Seafile Server on Oracle VPS.

### Hierarchy Sync
- **Documents/Photos:** Perpetual sync via `seafile-client`.
- **Media/Bulk:** Mounted on-demand from the `arch-slave` node.

