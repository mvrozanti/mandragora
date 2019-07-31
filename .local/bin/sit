#!/bin/bash
find -iname "*.jpg" -print0 | xargs -P8 -I{} -0 sh -c "exiftool -a `realpath \'{}\' | tee` | grep $@ > /dev/null && echo '{}'" 2>&1
