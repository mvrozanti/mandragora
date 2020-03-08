import os
import sys
from os import path as op
d = dir
for a in sys.argv:
    os.system(f'ptpython --vi -i {a}')
