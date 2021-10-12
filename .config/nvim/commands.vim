command! -bar -range=% Reverse <line1>,<line2>global/^/m<line1>-1
command RandomLine execute 'normal! '.(system('/bin/bash -c "echo -n $RANDOM"') % line('$')).'G'
command Jsonify execute ":%!python3 -m json.tool"
command JsBeautify execute ":%!slimit"
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')
command! -range=% RemoveDiacritics call s:RemoveDiacritics(<line1>, <line2>)
command ShowWhitespace :set list
command Rpc call system('echo -n' .
\   shellescape(expand('%:p'), 1) . '| xsel -i -b ') 
