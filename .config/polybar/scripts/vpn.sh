#!/bin/bash
pgrep -x openvpn >/dev/null && echo '%{u#0f0}%{F#0f0}%{+u}🖧' || echo '%{F-}%{-u}🖧'
