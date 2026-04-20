#!/usr/bin/env python3
import fileinput

normal = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
supers = '𝒶𝒷𝒸𝒹𝑒𝒻𝑔𝒽𝒾𝒿𝓀𝓁𝓂𝓃o𝓅𝓆𝓇𝓈𝓉𝓊𝓋𝓌𝓍𝓎𝓏'

for line in fileinput.input():
    for c in line:
        if c in normal:
            print(supers[normal.index(c)], end='', flush=True)
        else:
            print(c, end='', flush=True)
