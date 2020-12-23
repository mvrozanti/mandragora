" Automatically deletes all tralling whitespace on save.
" let blacklist = ['txt']
" autocmd BufWritePre  * if index(blacklist, &ft) < 0 | %s/\s\+$//e
"


" Sync tex pdf (doesnt work tho)
" function! Synctex()
"     execute "silent !zathura --synctex-forward " . line('.') . ":" . col('.') . ":" . bufname('%') . " " . g:syncpdf
"     redraw!
" endfunction
" map <C-enter> :call Synctex()<CR>


if has('persistent_undo')
    let myUndoDir = expand(vimDir . '/undodir')
    " Create dirs
    call system('mkdir ' . vimDir)
    call system('mkdir ' . myUndoDir)
    let &undodir = myUndoDir
    set undofile
endif
