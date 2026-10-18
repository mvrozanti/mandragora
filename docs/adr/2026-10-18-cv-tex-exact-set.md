# The CV's TeX is an exact `texlive.withPackages` set in the system closure

Date: 2026-10-18. Status: accepted.

## Context

`texliveFull` sat in `environment.systemPackages` as 5.85 GiB, 13,040
derivations and 2.0 s of every system evaluation. The only TeX consumer
on the machine is `~/Projects/cv` (`latexmk -xelatex`, biber, altacv),
built the same day; nothing else TeX-shaped has been built since 2024.

## Axis

Where does the CV's TeX live relative to the desktop's system closure,
and who decides which packages are in it?

## Directions considered

| Direction | Answer to the axis |
|---|---|
| Today: texliveFull | all of TeX Live in the closure; nobody chose the packages |
| **The CV's exact set, in the system** | the closure holds exactly what the CV was measured to read; the list lives in the system repo |
| Medium plus the extras | a broad scheme for documents that do not exist yet, plus the 13 the CV needs anyway |
| The CV owns its TeX | nothing TeX in the system; a shell.nix in the project, loaded by direnv |
| Stubs that fetch on first call | the system knows the set but ships stubs; the first call builds and roots it |

The deck traced seven scenarios through each (build, a normal switch,
a nixpkgs bump, a fresh install, a new package, another document,
3 a.m. debugging) with live criteria weights.

## Decision

The exact set: `scheme-small` plus `latexmk biber biblatex changepage
dashrule enumitem environ fontawesome ifmtarg logreq multirow tcolorbox
tikzfill titlesec trimspaces academicons babel-portuges lato`, in
`nix/modules/core/globals.nix`. The list was derived from the `.fls`
file lists of all four CV builds and proven by compiling all four with
only this set on PATH: identical output. 0.68 GiB, 3,626 derivations,
1.0 s eval. Lato and FontAwesome must stay in the set because xelatex
resolves them from texmf, not fontconfig.

## Accepted consequences

- **Gives up:** a document outside the CV fails with a named `.sty`
  until that package is added to the list and the system is switched
  (about 90 s). The 2021 thesis needs `abntex2` before it builds again.
- **Undo:** put `texliveFull` back on one line; two-way door.

## Acceptance test

`git -C ~/Projects/cv archive HEAD | tar -x -C <scratch> && make all`
with the plain system PATH produces `build/{en,ptbr}-{default,bot}.pdf`.
