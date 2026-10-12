#!/usr/bin/env python3
import os
import sys

sys.pycache_prefix = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "progress-hud", "bytecode")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from progress_hud import main

main()
