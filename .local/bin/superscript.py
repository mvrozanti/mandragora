#!/usr/bin/env python3
import fileinput

normal = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
supers = 'ᵃᵇᶜᵈᵉᶠᵍʰᶦʲᵏˡᵐⁿᵒᵖᵠʳˢᵗᵘᵛʷˣʸᶻᴬᴮᶜᴰᴱᶠᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᵠᴿˢᵀᵁⱽᵂˣʸᶻ'

for line in fileinput.input():
    for c in line:
        if c in normal:
            print(supers[normal.index(c)], end='', flush=True)
        else:
            print(c, end='', flush=True)
