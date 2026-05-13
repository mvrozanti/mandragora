# Gemini CLI — Mandragora

**Read \`AGENTS.md\` first.** It contains all universal rules, non-negotiables, and system context. This file adds Gemini-specific behavior only.

---

## Execution & Decision Discipline

Follow the **Decision discipline** in \`AGENTS.md\`: when a fork has a clearly reasonable default (naming, placement, minor adjacent fixes), make the call and keep moving. The user prefers proactivity over constant interruption for reversible, in-scope choices.

---

## AI Bridge Protocol

You are part of a multi-agent ecosystem collaborating alongside Claude Code, local Qwen models, and others.

- **Cross-agent handoffs:** see \`~/.ai-shared/rules/handoff.md\`. Tasks are not tracked under version control; ad-hoc state lives in \`~/.ai-shared/handoffs/\` (transient) and is consumed via \`/pickup\`.
- **Skills & Workflows:** Use skills defined in \`agent-skills/\` (e.g., \`nrp\` for splitting topical commits, \`gpu-lock\` for LLM/GPU work).
- **Rules & Templates:** Follow constraints in \`~/.ai-shared/rules/\` and \`~/.ai-shared/templates/\`.

---

## Git Safety Rule

When moving files to \`~/.ai-shared\`, **COPY** them. Do not move original physical files out of version control and replace them with symlinks. The authoritative files must live within the git repository (\`/etc/nixos/mandragora\`).

---

## Rebuilding

Any changes to the NixOS configuration must be applied by rebuilding. Use the wrapper script:

\`\`\`bash
mandragora-switch
\`\`\`

**Autonomous commit authorization:** You are authorized to perform the commit+build+push cycle via \`mandragora-switch\` after any in-scope modification. The script automatically generates a commit message using Gemini if you are in the environment (\`GEMINI_CLI=1\`).
