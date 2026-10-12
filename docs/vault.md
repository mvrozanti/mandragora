# Vault verdicts (Rule 22)

The knowledge vault at `~/Documents/mandragora-desktop-obsidian-vault/`
holds the *why* behind this repo. It is published at
[demo.mvr.ac](https://demo.mvr.ac), indexed by search engines. Every
commit an agent makes to this repo records a verdict about it in the
`Vault:` line of its message.

## The protocol, step by step

Do this before `git commit` (or before `mandragora-switch` when the
switch makes the commit for you).

1. Ask: does this change carry a reason a reader of the diff would not
   see? A decision between options, a constraint, a workaround, an
   incident lesson, a number someone measured. If not, skip to step 6.
2. Look for a note that already covers the topic:

   ```
   mandragora-vault find <two or three keywords>
   ```

3. If one fits, open it and **add or correct only the lines that need
   it**. Keep everything else exactly as it is.
4. If none fits, create one. The tool writes the frontmatter for you:

   ```
   mandragora-vault new <category> "<Title in plain words>"
   ```

   Categories: `agents concepts decisions features hosts incidents
   modules principles programs services`. Write the body under the
   heading: what was decided or learned, why, what it rules out.
   Link other notes with `[[Their Title]]`. Describe machines and
   devices, never identify them: "the phone", "the VPS's tailnet
   address", not a model number, a personal hostname or an address.
5. Commit the note (only the paths you name are committed):

   ```
   mandragora-vault commit -m "<what the note now explains>" "<note path>"
   ```

6. End the repo commit message with one of:

   ```
   Vault: decisions/<the note you wrote or patched>.md
   Vault: none (<three or more words on why nothing needs recording>)
   ```

   With `mandragora-switch` making the commit, pass it as a flag:
   `mandragora-switch --vault='none (only retunes a timeout)' "fix(x): …"`.

## What the tool refuses, and the fix

| Refusal | Fix |
|---|---|
| no body yet | write the body, commit again |
| a note with this title already exists | patch that note instead |
| N of its M lines are gone; a rewrite | `git -C <vault> checkout HEAD -- '<path>'`, then change only what is wrong |
| frontmatter damaged, keys or type changed | put the `---` block back exactly |
| agents do not delete notes | restore the file; deletions are the human's, in Obsidian |
| renamed, but N notes still link the old name | move it back, then `mandragora-vault rename '<path>' "<new title>"`, which rewrites every link in the same commit |
| title has characters Obsidian cannot link, or a `/` | pick a plain title; a `/` makes nested folders |
| `[[X]]` matches no note | link an existing title (`mandragora-vault find X`) or drop the brackets |
| email address / looks like a token | remove it; describe the mechanism, never the value; rotate if it was real |
| names a specific tailnet or LAN address | describe the machine instead ("the VPS's tailnet address") |
| note was last changed N days ago | cite the note you changed for this commit, or `Vault: none (already documented in <title>)` |

Never get around a refusal with `--no-verify`, raw `git` in the vault,
or by editing `.sync-ledger` or `.sync-state` by hand. The vault has its
own pre-commit hook that applies the same checks to a raw `git commit`.

## Where verdicts live

- **New commits:** the `Vault:` line in the commit message. It survives
  rebases, so it is the only home for commits not yet on master.
- **Commits already on master without one** (human commits, history
  before the rule): `.sync-ledger` in the vault, appended through
  `mandragora-vault verdict <commit> --note <path>` or
  `--none "<reason>"`, or in bulk with `--from-file` (TSV:
  `commit<TAB>note|none<TAB>path or reason`).
- **Coverage:** `mandragora-vault status` counts commits since the
  baseline in `.sync-state` by where their verdict lives;
  `--missing` lists the ones without. It also lists note names Obsidian
  cannot link, and notes left uncommitted. Those wait for the session
  that wrote them: nobody else commits another author's note.

## Publishing

An agent-run `mandragora-switch` ends with `mandragora-vault publish`:

1. It takes the vault commits since `refs/heads/published` (what is live).
2. Deterministic checks: secrets, deletions, and notes that lost over a
   quarter of their lines since the last publish.
3. Haiku reads every added line for private material: credentials,
   other people's personal data, SSIDs, addresses, employer
   specifics, the home connection, device models, personal hostnames,
   tailnet and LAN host addresses, financial identifiers.
4. Clean: the committed tree (never the working tree, never the
   ledger) is deployed with `compose/demo/publish-vault.sh`, which
   writes only `vault/` and `graph.json` (the page belongs to
   `compose/demo/deploy.sh`), and
   `published` moves forward.
5. Doubtful: nothing is deployed, `mandragora-vault status` lists
   the items with the sensitive part masked, and a desktop notification
   fires. Fix the note and commit it; the next agent switch retries.
   A human can override at a terminal with `mandragora-vault publish
   --approve`.
6. No model reachable: nothing is published, and the next switch retries.

Human-run switches neither require verdicts nor publish. Agents are
recognised by `MANDRAGORA_AGENT`, `AI_AGENT`, `CLAUDECODE` or
`GEMINI_CLI` in the environment, or by a switch without a terminal. A
new agent harness sets `MANDRAGORA_AGENT=<name>`.

Why this design, and what it replaced: vault note
`decisions/Vault verdicts on agent commits.md`.
