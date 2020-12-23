command Reversefilelines g/^/m0
command RandomLine execute 'normal! '.(system('/bin/bash -c "echo -n $RANDOM"') % line('$')).'G'
command  Jsonify execute ":%!python3 -m json.tool"
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')
command! -range=% RemoveDiacritics call s:RemoveDiacritics(<line1>, <line2>)
