set encoding=utf-8
let g:colorizer_auto_color = 1
" map // V//
set nofoldenable
set foldmethod=manual
let g:ycm_global_ycm_extra_conf = "~/.vim/bundle/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py"
let g:ycm_key_list_select_completion = ['<TAB>', '<Down>', '<CR>']
let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_key_list_stop_completion = ['<Enter>']

" hits bong: 
vnoremap ( xi()<Esc>PF(i
vnoremap " xi""<Esc>PF"i
nnoremap yF maggyG'a
inoremap <C-Space> <C-X><C-O>
nnoremap <Space><Space> <Esc>/<+><CR>"_3xi
nnoremap dl v$hxJhv0w"_x
nnoremap cW eF_hvbc
" this is basically ci( -> nnoremap c( $F(lvt)c
vnoremap - $h
nnoremap x "_x
nnoremap <C-i> :mark x<CR>
nnoremap <C-u> 'x

" vnoremap ) 
vnoremap <C-r> "hy:%s/<C-r>h//gc<left><left><left>
nnoremap <Del> "_<Del>

nmap S ysiw
" nnoremap <Space><Space> f<Space>i

" general shortcuts
inoremap she<tab> #!/bin/bash<Esc>o
inoremap re<tab> return<Space>
inoremap fori<tab> for(int i=0; i < ; i++){<CR>}<Esc>3Bla


" python shortcuts
autocmd FileType python inoremap ci<tab> code.interact(local=locals())<Esc> 
autocmd FileType python inoremap ld<tab> LOG.debug()<Esc>i
autocmd FileType python inoremap pr<tab> print()<Esc>i
autocmd FileType python inoremap she<tab> #!/usr/bin/env python
autocmd FileType python inoremap Fa<tab> False
autocmd FileType python inoremap Tr<tab> True

" autocmd FileType c set makeprg=gcc\ -O2\ -g\ -Wall\ -Wextra\ -o'%<'\ '%'\ -lm ; ./%\:r

autocmd FileType c inoremap pr<tab> printf("", <+>);<Esc>7hi

" bash shortcuts
" autocmd FileType sh     

" remove highlight
nnoremap <Esc><Esc> :nohl<CR>

" tabs
nnoremap gJ gT
nnoremap gK gt

" nnoremap M :tabedit %<CR>
nnoremap <C-N> :tabe<CR>
nnoremap [ <C-W>

" WIP
nnoremap <buffer> <F5> <Esc>:w<CR>:call system(b:run_script)<CR>
autocmd FileType c nnoremap <buffer> <F5> <Esc>:make<CR>

" remap mark
nnoremap , '

" general
command Reversefilelines g/^/m0
command Jsonify execute ":%!python3 -m json.tool"

" if has('persistent_undo')      "check if your vim version supports it
" Put plugins and dictionaries in this dir (also on Windows)
let vimDir = '$HOME/.vim'
let &runtimepath.=','.vimDir
inoremap QQ <Esc>:q!<CR>

" netbeans<3
inoremap <C-E> <Esc> ddi
nnoremap <C-E> dd
vnoremap <C-E> d

set hlsearch
set nocompatible  " be iMproved, required # ??
set nosmd   " short for 'showmode' for powerline
filetype off  " required
set exrc

"move vim splits
nnoremap <C-LEFT> :10winc <<CR>
nnoremap <C-UP> :10wincmd +<CR>
nnoremap <C-RIGHT> :10wincmd ><CR> 
nnoremap <C-DOWN> :10wincmd -<CR>

"autocomplete colors
"highlight Pmenu ctermfg=2 ctermbg=4 guifg=1 guibg=4

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

"Clipboard -> cp,cv 
Plugin 'christoomey/vim-system-copy'
map y cp
map yy YY
set clipboard=unnamed,unnamedplus
"set paste " < does not work with jedi, but works w/ YCM
let g:system_copy#copy_command='xclip -sel clipboard -i'
let g:system_copy#paste_command='xclip -sel clipboard -o'

Plugin 'ehamberg/vim-cute-python'

"==== plugin manager
Plugin 'VundleVim/Vundle.vim'

Plugin 'pangloss/vim-javascript'
set conceallevel=1
let g:javascript_conceal_function = "ƒ"
let g:javascript_plugin_jsdoc = 1
let g:javascript_conceal_null                 = "ø"
let g:javascript_conceal_this                 = "@"
let g:javascript_conceal_return               = "⇚"
let g:javascript_conceal_undefined            = "¿"
let g:javascript_conceal_NaN                  = "ℕ"
let g:javascript_conceal_prototype            = "¶"
let g:javascript_conceal_static               = "•"
let g:javascript_conceal_super                = "Ω"
let g:javascript_conceal_arrow_function       = "⇒"
let g:javascript_plugin_ngdoc = 1
let g:javascript_plugin_flow = 1

let g:CXXFLAGS='-std=c++11'
" ==== File tree
Plugin 'scrooloose/nerdtree'

" ==== overwrite vim banner
Plugin 'mhinz/vim-startify'
Plugin 'mhinz/vim-signify'

" ==== Completion
Plugin 'Valloric/YouCompleteMe'
Plugin 'davidhalter/jedi-vim'

" ==== Git
Plugin 'airblade/vim-gitgutter'
Plugin 'tpope/vim-fugitive'

" ==== syntax helpers
Plugin 'scrooloose/syntastic'
let g:syntastic_javascript_checkers = ['eslint']
" let g:syntastic_java_checkers=['eclim']
Plugin 'tpope/vim-surround'
Plugin 'chrisbra/Colorizer'
Plugin 'chrisbra/unicode.vim'

Plugin 'othree/yajs.vim'
Plugin 'mitsuhiko/vim-jinja'

" ==== moving / seraching
Plugin 'easymotion/vim-easymotion'
Plugin 'kien/ctrlp.vim'

" ==== snippets
Plugin 'SirVer/ultisnips'

" ==== AUTOCOMPLETE PAIRS
" Plugin 'jiangmiao/auto-pairs'
" let g:AutoPairsFlyMode = 1

" ==== PLUGIN THEMES
"Plugin 'morhetz/gruvbox'

call vundle#end()
filetype plugin indent on

" ==== Colors and other basic settings
" powerline
set rtp+=$HOME/.local/lib/python3.7/site-packages/powerline/bindings/vim/
set laststatus=2
set t_Co=256
set guifont=Monospace\ 10
set fillchars+=vert:\$
syntax enable
"set background=
set ruler
set hidden
set number
set relativenumber
set laststatus=2
set smartindent
set st=4 sw=4 et
set shiftwidth=4
set tabstop=4
"let &colorcolumn="80"
:set guioptions-=m  "remove menu bar
:set guioptions-=T  "remove toolbar
:set guioptions-=r  "remove right-hand scroll bar
:set guioptions-=L  "remove left-hand scroll bar


" ==== NERDTREE
let NERDTreeIgnore = ['\.pyc$', '\.o$', '\.so$', '\.a$', '\.swp', '*\.swp', '\.swo', '\.swn', '\.swh', '\.swm', '\.swl', '\.swk', '\.sw*$', '[a-zA-Z]*egg[a-zA-Z]*', '[a-zA-Z]*cache[a-zA-Z]*', '.DS_Store']

let NERDTreeShowHidden=1
let g:NERDTreeWinPos="left"
let g:NERDTreeDirArrows=0
map <C-t> :NERDTreeToggle<CR>

" ==== Syntastic
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
set statusline+=%f
"let g:syntastic_javascript_checkers = ['eslint']
"let g:syntastic_cpp_compiler = 'clang++'
let g:syntastic_cpp_compiler_options = '-std=c++11 -stdlib=libc++'
let g:syntastic_javascript_mri_args = "--config=$HOME/.jshintrc"
let g:syntastic_python_checkers = [ 'pylint', 'flake8', 'pep8', 'pyflakes', 'python3', 'pymode']
let g:syntastic_yaml_checkers = ['jsyaml']
let g:syntastic_html_tidy_exec = 'tidy5'

" === flake8
let g:flake8_show_in_file=1

" ==== snippets
let g:UltiSnipsExpandTrigger="<A-ENTER>"
let g:UltiSnipsJumpForwardTrigger="<A-ENTER>"
let g:UltiSnipsJumpBackwardTrigger="<A-BACKSPACE>"
" If you want :UltiSnipsEdit to split your window.
let g:UltiSnipsEditSplit="vertical"

" ==== moving around
nmap <silent> <A-Up> :wincmd k<CR>
nmap <silent> <A-Down> :wincmd j<CR>
nmap <silent> <A-Left> :wincmd h<CR>
nmap <silent> <A-Right> :wincmd l<CR>


" ==== custom commands
Plugin 'christoomey/vim-tmux-navigator'
Plugin 'kien/rainbow_parentheses.vim'
au VimEnter * RainbowParenthesesToggle
au Syntax * RainbowParenthesesLoadRound
au Syntax * RainbowParenthesesLoadSquare
au Syntax * RainbowParenthesesLoadBraces
" let g:tmux_navigator_no_mappings = 1

" nnoremap <silent> <A-Left >  :TmuxNavigateLeft<cr>
" nnoremap <silent> <A-Down >  :TmuxNavigateDown<cr>
" nnoremap <silent> <A-Up   >  :TmuxNavigateUp<cr>
" nnoremap <silent> <A-Right>  :TmuxNavigateRight<cr>
set mouse=c
let g:BASH_Ctrl_j = 'off'

" ==== Easymotion
let g:EasyMotion_do_mapping = 0
let g:EasyMotion_smartcase = 1
nmap f <Plug>(easymotion-s)

autocmd FileType c,cpp,java,scala,javascript,css                    let b:comment_leader = '// '
autocmd FileType conf,fstab,sh,ruby,python                          let b:comment_leader = '# '
autocmd FileType swipl,perl,tex                                     let b:comment_leader = '% '
autocmd FileType mail                                               let b:comment_leader = '> '
autocmd FileType vim                                                let b:comment_leader = '" '
autocmd FileType lisp                                               let b:comment_leader = '; '
autocmd FileType javascript                                         let b:run_script = '!clear;xvkbd -window Firefox -text "\Cr" && xdotool keydown alt key Tab; sleep 2.001; xdotool keyup alt'
autocmd FileType javascript                                         set omnifunc=javascriptcomplete#CompleteJS
autocmd FileType python                                             let b:run_script = '! clear;python3 %'
autocmd FileType python                                             let g:pymode_python = 'python3'
autocmd FileType cpp                                                let b:run_script = '! clear; make && !%:r'
" autocmd FileType *.c                                                  let b:run_script='gcc\ %\ &&\ ./!%:r.out'

inoremap <A-Left> <ESC>h
inoremap <A-Down> <ESC>j
inoremap <A-Up> <ESC>k
inoremap <A-Right> <ESC>l

nnoremap <C-W> <Esc>:q<CR> 
inoremap <C-W> <Esc>:q<CR>
nnoremap <C-S> <Esc>:w<CR>
inoremap <C-S> <Esc>:w<CR>

nnoremap _ :split<CR>
vnoremap _ :split<CR>
nnoremap \| :vsplit<CR>
vnoremap \| :vsplit<CR>

inoremap jk <Esc>l
inoremap JK <Esc>l
vnoremap JK <Esc> 

" ==== Visual timeouts
set timeoutlen=1000 ttimeoutlen=0

" reverse J
nnoremap <C-o> i<CR><Esc> 

" endl but not really
" this is actually not needed since d$
" nnoremap - $h
" vnoremap - $h

" nnoremap F gg=G''
nnoremap QQ :q!<CR>

colorscheme peachpuff
" let g:EclimFileTypeValidate = 0
let g:syntastic_java_javac_config_file_enabled = 1

" kill REPLACE mode
inoremap <Insert> <Esc>

" Commenting blocks of code.
vnoremap <silent> // :<C-B>silent <C-E>s/^/<C-R>=escape(b:comment_leader,'\/')<CR>/<CR>:nohlsearch<CR>
vnoremap <silent> <leader><leader> :<C-B>silent <C-E>s/^\V<C-R>=escape(b:comment_leader,'\/')<CR>//e<CR>:nohlsearch<CR>
nnoremap <silent> <leader><leader> :<C-B>silent <C-E>s/^\V<C-R>=escape(b:comment_leader,'\/')<CR>//e<CR>:nohlsearch<CR>

" Keep undo history across sessions by storing it in a file
if has('persistent_undo')
    let myUndoDir = expand(vimDir . '/undodir')
    " Create dirs
    call system('mkdir ' . vimDir)
    call system('mkdir ' . myUndoDir)
    let &undodir = myUndoDir
    set undofile
endif

