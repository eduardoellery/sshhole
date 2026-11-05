#!/bin/sh
# 1ª chamada: senha errada curta; demais: 300 bytes
f=/tmp/askpass.count; n=$(cat $f 2>/dev/null || echo 0); echo $((n+1)) > $f
if [ "$n" = 0 ]; then echo errada; else printf 'A%.0s' $(seq 1 300); echo; fi
