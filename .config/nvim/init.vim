so $HOME/.config/nvim/settings.vim
so $HOME/.config/nvim/functions.vim
so $HOME/.config/nvim/let.vim
so $HOME/.config/nvim/commands.vim
so $HOME/.config/nvim/autocommands.vim
so $HOME/.config/nvim/general.vim
so $HOME/.config/nvim/plug.vim
so $HOME/.config/nvim/map.vim
so $HOME/.config/nvim/post-init.vim

" Plug 'evanleck/vim-svelte', {'branch': 'main'}
Plug 'leafOfTree/vim-svelte-plugin'
Plug 'pangloss/vim-javascript'
Plug 'HerringtonDarkholme/yats.vim'
Plug 'prettier/vim-prettier', { 'do': 'npm install' }
Plug 'Shougo/context_filetype.vim'
Plug 'codechips/coc-svelte', {'do': 'npm install'}

" Prettier Settings
let g:prettier#quickfix_enabled = 0
let g:prettier#autoformat_require_pragma = 0
au BufWritePre *.css,*.svelte,*.pcss,*.html,*.ts,*.js,*.json PrettierAsync

if !exists('g:context_filetype#same_filetypes')
  let g:context_filetype#filetypes = {}
endif

let g:context_filetype#filetypes.svelte =
\ [
\   {'filetype' : 'javascript', 'start' : '<script>', 'end' : '</script>'},
\   {
\     'filetype': 'typescript',
\     'start': '<script\%( [^>]*\)\? \%(ts\|lang="\%(ts\|typescript\)"\)\%( [^>]*\)\?>',
\     'end': '',
\   },
\   {'filetype' : 'css', 'start' : '<style \?.*>', 'end' : '</style>'},
\ ]

let g:ft = ''

Plug 'preservim/nerdcommenter'
"
" NERDCommenter settings

let g:NERDSpaceDelims = 1
let g:NERDCompactSexyComs = 1
let g:NERDCustomDelimiters = { 'html': { 'left': '' } }

" Align comment delimiters to the left instead of following code indentation
let g:NERDDefaultAlign = 'left'

fu! NERDCommenter_before()
  if (&ft == 'html') || (&ft == 'svelte')
    let g:ft = &ft
    let cfts = context_filetype#get_filetypes()
    if len(cfts) > 0
      if cfts[0] == 'svelte'
        let cft = 'html'
      elseif cfts[0] == 'scss'
        let cft = 'css'
      else
        let cft = cfts[0]
      endif
      exe 'setf ' . cft
    endif
  endif
endfu

fu! NERDCommenter_after()
  if (g:ft == 'html') || (g:ft == 'svelte')
    exec 'setf ' . g:ft
    let g:ft = ''
  endif
endfu
