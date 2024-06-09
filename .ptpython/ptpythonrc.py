# ptpython-exclusive

__all__ = ["configure"]

def configure(repl):
    repl.confirm_exit = True

# extra

import os
import sys
from os import path as op
d = dir
for a in sys.argv:
    os.system(f'ptpython --vi -i {a}')

