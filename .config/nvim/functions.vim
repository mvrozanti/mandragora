fun! SetupCommandAlias(from, to)
  exec 'cnoreabbrev <expr> '.a:from
        \ .' ((getcmdtype() is# ":" && getcmdline() is# "'.a:from.'")'
        \ .'? ("'.a:to.'") : ("'.a:from.'"))'
endfun

" Remove diacritical signs from characters in specified range of lines.
" Examples of characters replaced: á -> a, ç -> c, Á -> A, Ç -> C.
function! RemoveDiacritics(line1, line2)
  let diacs = 'áâãàçéêíóôõüú'  " lowercase diacritical signs
  let repls = 'aaaaceeiooouu'  " corresponding replacements
  let diacs .= toupper(diacs)
  let repls .= toupper(repls)
  let all = join(getline(a:line1, a:line2), "\n")
  call setline(a:line1, split(tr(all, diacs, repls), "\n"))
endfunction


function! Killit()
    let l:buf_count = len(getbufinfo({'buflisted':1}))
    try
        if l:buf_count == 1
            try
                try
                    :silent q
                catch
                    :echo 'There are contents still in the buffer.'
                endtry
            catch
                :wq
            endtry
        else
            :bd
        endif
    catch
        if &buftype ==# "nofile"
            :q
        endif
    endtry
endfunction


function! Synctex()
    " remove 'silent' for debugging
    execute "silent !zathura --synctex-forward " . line('.') . ":" . col('.') . ":" . bufname('%') . " " . bufname('%')[:-5]. ".pdf"
    redraw!
endfunction
