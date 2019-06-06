fun! SetupCommandAlias(from, to)
  exec 'cnoreabbrev <expr> '.a:from
        \ .' ((getcmdtype() is# ":" && getcmdline() is# "'.a:from.'")'
        \ .'? ("'.a:to.'") : ("'.a:from.'"))'
endfun

call SetupCommandAlias("jsonify","%!python -m json.tool")
map <A-F> mzgg=G`zzz
xnoremap p "_dP
map / /\c
nnoremap vt v%
vnoremap / y/<C-r><C-w><CR>
vnoremap ? y:%s/<C-r><C-w>//gn<CR>
nnoremap <A-p> o<A-p>
" Automatically deletes all tralling whitespace on save.
" let blacklist = ['txt']
" autocmd BufWritePre  * if index(blacklist, &ft) < 0 | %s/\s\+$//e
autocmd BufWritePost *.tex silent! !pdflatex % ; pdflatex -synctex=1 % 
nnoremap <C-o> :call Synctex()<CR>
autocmd BufWritePost *.bib silent! !bibtex %:r ; pdflatex %:r.tex ; pdflatex -synctex=1 %:r.tex 

" Sync tex pdf (doesnt work tho)
" function! Synctex()
"     execute "silent !zathura --synctex-forward " . line('.') . ":" . col('.') . ":" . bufname('%') . " " . g:syncpdf
"     redraw!
" endfunction
" map <C-enter> :call Synctex()<CR>
" 
map Q <NOP>
imap silent <C-h> <A-b>
imap silent <C-l> <A-w>
imap silent <C-Left> <A-b>
imap silent <C-Right> <A-w>
inoremap <A-Backspace> <A-c>iw
nnoremap <A-Backspace> viwd
inoremap jk <Esc>l
inoremap jK <Esc>l
inoremap Jk <Esc>l
inoremap JK <Esc>l
vnoremap JK <Esc>
inoremap QQ <Esc>:q!<CR>
nnoremap QQ :q!<CR>
inoremap <Insert> <Esc>

" Keep undo history across sessions by storing it in a file
" if has('persistent_undo')      "check if your vim version supports it
" Put plugins and dictionaries in this dir (also on Windows)
let vimDir = '$HOME/.vim'
let &runtimepath.=','.vimDir
if has('persistent_undo')
    let myUndoDir = expand(vimDir . '/undodir')
    " Create dirs
    call system('mkdir ' . vimDir)
    call system('mkdir ' . myUndoDir)
    let &undodir = myUndoDir
    set undofile
endif

call plug#begin()
" Plug 'Yggdroot/indentLine'
Plug 'christoomey/vim-tmux-navigator'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
autocmd FileType prolog setlocal commentstring=%\ %s
autocmd FileType perl   setlocal commentstring=%\ %s
Plug 'richq/vim-cmake-completion'
vmap <C-Space> gc
nmap <C-Space> gcc
Plug 'dbmrq/vim-ditto'
au FileType tex DittoOn
Plug 'scrooloose/vim-slumlord'
" Plug 'aklt/plantuml-syntax'
nmap S ysiw
let g:tmux_navigator_no_mappings = 0
nnoremap <A-Left>  :TmuxNavigateLeft<cr>
nnoremap <A-Down>  :TmuxNavigateDown<cr>
nnoremap <A-Up>    :TmuxNavigateUp<cr>
nnoremap <A-Right> :TmuxNavigateRight<cr>

let g:colorizer_auto_color = 1

set nofoldenable
set foldmethod=indent
" Plug 'Valloric/YouCompleteMe'
let g:ycm_global_ycm_extra_conf = "~/.vim/bundle/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py"
let g:ycm_key_list_select_completion = ['<TAB>']
let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_key_list_stop_completion = ['<Enter>']
" let g:ycm_server_python_interpreter = "/usr/bin/python"
" let g:ycm_path_to_python_interpreter="/usr/bin/python"
let g:ycm_filetype_whitelist = {
			\ "c":1,
			\ "cpp":1,
			\ "sh":1,
			\ "zsh":1,
			\ "python":1,
			\ }
let g:vebugger_leader = '\'
if !exists('g:vdebug_options')
    let g:vdebug_options = {}
endif
let g:vdebug_options.break_on_open = 0

set visualbell
set t_vb=

" hits bong:
" vnoremap <silent> <C-c> :<C-B>silent <C-E>s/^/<C-R>=escape(b:comment_leader,'\/')<CR>/<CR>:noh<CR>
" nnoremap : q:i
" nmap <silent> M    "_yiw:s/\(\%#\w\+\)\(\_W\+\)\(\w\+\)/\3\2\1/<CR><C-O> *N*<Esc><Esc>
nnoremap yD y$
nnoremap <A-i> f(a
inoremap <A-i> <Esc>f(a
nnoremap <A-I> <Esc>f,a
inoremap <A-I> <Esc>f,a
vnoremap <C-f> y/<C-R>"<CR>
nnoremap <CR> i<CR><Esc>
vnoremap ( <Esc>a)<Esc>gvo<Esc>i(<Esc>i
nnoremap yF maggyG'a
nnoremap <Space><Space> <Esc>/<+><CR>"_3x:noh<CR>i
nnoremap ZZ <Esc>?<+><CR>"_3xi
nnoremap dl v$hxJhv0w"_x
nnoremap c_ ct_
nnoremap dA F(vbdf)xB
nmap dS bysw<Space><Space>ds)
vnoremap - $h
nnoremap <C-i> :mark x<CR>
nnoremap <C-u> 'x
inoremap {<CR> {<CR>}<Esc>k$o
vnoremap <CR> c<CR>

nnoremap <C-Tab> gK

" Goyo
map <F2> :Goyo 200x200<CR>
" Case insensitive search by default

" Replace visual selection
vnoremap <C-r> "hy:.,$s/<C-r>h//gc<left><left><left>
vnoremap <C-h> "hy:%s/<C-r>h//gc<left><left><left>
" Delete where does not contain
vnoremap D "hy:%g!/<C-r>h/d"
" Del and x should not affect clipboard
nnoremap <Del> "_<Del>
nnoremap x "_x


" general shortcuts
inoremap she<tab> #!/bin/bash<Esc>o
inoremap re<tab> return<Space>
inoremap fori<tab> for(int i=0; i < ; i++){<CR>}<Esc>3Bla
inoremap forj<tab> for(int j=0; j < ; j++){<CR>}<Esc>3Bla

" javascript shortcuts
autocmd FileType javascript inoremap repl<tab> require('repl').start('> ').context.<+> = <+>;<Esc>
autocmd FileType javascript inoremap tr<tab> true
autocmd FileType javascript inoremap fa<tab> false
autocmd FileType javascript inoremap cl<tab> console.log()<Esc>i
autocmd FileType javascript inoremap fn<tab> function(){<CR><+><CR>}<Esc>2kf(l
autocmd FileType javascript inoremap she<tab> #!/usr/bin/env node

" java shortcuts
autocmd FileType java inoremap psvm<tab> public static void main(String args[]){<CR>}
autocmd FileType java map <silent> <F6> :Java<CR><CR>
autocmd FileType java inoremap pr<tab> private<Space>
autocmd FileType java inoremap pu<tab> public<Space>
autocmd FileType java inoremap sout<tab> System.out.println()<Esc>i
autocmd FileType java inoremap fa<tab> false
autocmd FileType java inoremap tr<tab> true

" python shortcuts
" %s/print\s\(.\+\)/print(\1)/g
autocmd FileType python inoremap im<tab> import<Space>
autocmd FileType python inoremap ci<tab> code.interact(local=globals().update(locals()) or globals())<Esc>
autocmd FileType python inoremap pdbt<tab> pdb.set_trace()<Esc>
autocmd FileType python set makeprg=python\ %
autocmd FileType python map <silent> <F6> :make<CR><CR>
autocmd FileType python inoremap ld<tab> LOG.debug()<Esc>i
autocmd FileType python inoremap pr<tab> print()<Esc>i
autocmd FileType python inoremap inm<tab> if __name__ == '__main__':<CR>
autocmd FileType python inoremap she<tab> #!/usr/bin/env python
autocmd FileType python inoremap Fa<tab> False
autocmd FileType python inoremap Tr<tab> True
autocmd FileType python inoremap wh<tab> while :<Esc>i
autocmd FileType python inoremap trycatch<tab> try:<CR><+><CR>except Exception as e: print(e)

" autocmd FileType c set makeprg=gcc\ -O2\ -g\ -Wall\ -Wextra\ -o'%<'\ '%'\ -lm ; ./%\:r

autocmd FileType c,cpp,lex inoremap st<tab> static 
autocmd FileType c,cpp,lex inoremap im<tab> int main(){}<Esc>i<CR><Esc>O
autocmd FileType c,cpp,lex inoremap uns<tab> using namespace std;<CR>
autocmd FileType c,cpp,lex inoremap in<tab> #include<><Esc>i
autocmd FileType c,lex inoremap so<tab> sizeof()<Esc>i
autocmd FileType c,cpp,lex inoremap pr<tab> printf("\n", <+>);<Esc>9hi
autocmd FileType c,cpp,lex inoremap fn<tab> <+> <+>(<+>){<CR>}<Esc>O
autocmd FileType c,cpp,java,lex inoremap sw<tab> switch(){<CR>case <+>:<CR>break;<CR>}<Esc>3kwa
autocmd FileType c,cpp,java,lex inoremap wh<tab> while(){<CR>}<Esc>kwa
autocmd FileType c,cpp,java,lex inoremap if<tab> if(){<CR>}<Esc>kwa

" bash shortcuts
" autocmd FileType sh

" remove highlight
nnoremap <Esc><Esc> :noh<CR>

" tabs
nnoremap gJ gT
nnoremap gK gt

nnoremap <C-N> :tabe<CR>
nnoremap [ <C-W>

nnoremap , '

" general
command Reversefilelines g/^/m0
command Jsonify execute ":%!python3 -m json.tool"

" netbeans bad habits
inoremap <C-E> <Esc> "_ddi
nnoremap <C-E> "_dd
vnoremap <C-E> "_d

set hlsearch
set nocompatible
set nosmd   " short for 'showmode' for powerline
filetype off  " required
set exrc

"move vim splits
nnoremap <S-H>      :5winc <<CR>
nnoremap <S-K>      :5winc +<CR>
nnoremap <S-L>      :5winc ><CR>
nnoremap <S-U>      :5winc -<CR>

"autocomplete colors
"highlight Pmenu ctermfg=2 ctermbg=4 guifg=1 guibg=4
set conceallevel=0

" === LSP ===
Plug 'neoclide/coc.nvim', {'tag': '*', 'do': { -> coc#util#install()}}
inoremap <silent><expr> <c-space> coc#refresh()
nmap <silent> <leader>w <Plug>(coc-diagnostic-next)
inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<cr>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
nnoremap <A-r> :call CocAction('rename')<CR>
" inoremap <silent><expr> <TAB>
"       \ pumvisible() ? "\<C-n>" :
"       \ <SID>check_back_space() ? "\<TAB>" :
"       \ coc#refresh()
set hidden
Plug 'tommcdo/vim-exchange'

Plug 'jiangmiao/auto-pairs'

Plug 'godlygeek/tabular'

Plug 'junegunn/goyo.vim'

Plug 'realincubus/vim-clang-refactor'

Plug 'jaxbot/browserlink.vim'

Plug 'sakhnik/nvim-gdb', { 'do': ':!./install.sh \| UpdateRemotePlugins' }
"
"Clipboard -> cp,cv
" Plug 'christoomey/vim-system-copy'
" map y cp
" map yy YY
set clipboard=unnamed,unnamedplus
" let g:system_copy#copy_command='xclip -sel clipboard -i'
" let g:system_copy#paste_command='xclip -sel clipboard -o'

" Plug 'mvrozanti/vim-cute-python'
Plug 'mvrozanti/vim-cute-cpp'

" C/C++ debugging
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
Plug 'idanarye/vim-vebugger'
nnoremap <F5>   :VBGcontinue<CR>
nnoremap <F6>   :VBGstartGDB %:r<CR>
nnoremap <F7>   :VBGstepIn<CR>
nnoremap <F8>   :VBGstepOver<CR>
nnoremap <C-F8> :VBGtoggleBreakpointThisLine<CR>
nnoremap <F10>  :VBGstepOut<CR>

Plug 'pangloss/vim-javascript'
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

" ==== File Browsing
" Plug 'tpope/vim-vinegar'
Plug 'scrooloose/nerdtree'
Plug 'ryanoasis/vim-devicons'
map <C-t> :NERDTreeToggle<CR>
let NERDTreeIgnore = ['\.pyc$', '\.o$', '\.so$', '\.a$', '\.swp', '*\.swp', '\.swo', '\.swn', '\.swh', '\.swm', '\.swl', '\.swk', '\.sw*$', '[a-zA-Z]*egg[a-zA-Z]*', '[a-zA-Z]*cache[a-zA-Z]*', '.DS_Store']
let g:NERDTreeQuitOnOpen=1
let g:NERDTreeShowHidden=1
let g:NERDTreeWinPos="left"
let g:NERDTreeDirArrows=0

let g:netrw_banner=0
let g:netrw_browse_split=4
let g:netrw_altv=1
let g:netrw_liststyle=3
" let g:netrw_list_hide=netrw_gitignore#Hide()


" ==== Refactoring for C-family
Plug 'vim-scripts/a.vim'
" Plug 'vim-scripts/ShowMarks'

" Plug 'bbchung/clighter8'

" ==== overwrite vim banner
Plug 'mhinz/vim-startify'
let g:startify_session_autoload = 1
" Plug 'mhinz/vim-signify'

" ==== Completion
Plug 'OmniSharp/omnisharp-vim'
Plug 'markwoodhall/vim-nuget'
Plug 'Shougo/deoplete.nvim'
Plug 'mattn/webapi-vim'
Plug 'junegunn/fzf.vim', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
set completeopt=longest,menuone,preview
" let g:OmniSharp_proc_debug = 1
let g:OmniSharp_server_use_mono = 1
" function! s:check_back_space() abort
"   let col = col('.') - 1
"   return !col || getline('.')[col - 1]  =~ '\s'
" endfunction


" ==== Git
Plug 'airblade/vim-gitgutter'
" Plug 'tpope/vim-fugitive'

" ==== syntax helpers
" Plug 'scrooloose/syntastic'
" let g:syntastic_javascript_checkers = ['eslint']
" let g:syntastic_java_checkers=['eclim']
Plug 'chrisbra/Colorizer'
Plug 'chrisbra/unicode.vim'

Plug 'othree/yajs.vim'
Plug 'mitsuhiko/vim-jinja'

" ==== moving / seraching
Plug 'easymotion/vim-easymotion'
Plug 'kien/ctrlp.vim'
let g:ctrlp_show_hidden=1

" ==== snippets
Plug 'SirVer/ultisnips'

filetype plugin indent on

" ==== Colors and other basic settings
set laststatus=2
set t_Co=256
set fillchars+=vert:\$
syntax enable
set lbr
set ruler
set hidden
set number
set relativenumber
set laststatus=2
set smartindent
set tabstop=4 sw=4 et
set shiftwidth=4
" :set guioptions-=m  "remove menu bar
" :set guioptions-=T  "remove toolbar
" :set guioptions-=r  "remove right-hand scroll bar
" :set guioptions-=L  "remove left-hand scroll bar

Plug 'danro/rename.vim'

" Real-time markdown editing
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app & yarn install'  }
" let g:mkdp_markdown_css = '~/darkdown.css'
Plug 'terryma/vim-expand-region'
map + <Plug>(expand_region_expand)
map - <Plug>(expand_region_shrink)
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
let g:airline_powerline_fonts = 1
let g:airline_theme='atomic'
call plug#end()

" ==== Syntastic
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
set statusline+=%#warningmsg#
" set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
set statusline+=%f
"let g:syntastic_javascript_checkers = ['eslint']
"let g:syntastic_cpp_compiler = 'clang++'
let g:syntastic_quiet_messages = { "regex": [
        \ '\mpossible unwanted space at "{"',
        \ '\Delete this space to maintain correct pagereferences',
        \ 'Wrong length of dash may have been used.'] }
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
set mouse=c
let g:BASH_Ctrl_j = 'off'

" ==== Easymotion
let g:EasyMotion_do_mapping = 0
let g:EasyMotion_smartcase = 1
nmap f <Plug>(easymotion-s)

autocmd FileType javascript                                         let b:run_script = '!clear;xvkbd -window Firefox -text "\Cr" && xdotool keydown alt key Tab; sleep 2.001; xdotool keyup alt'
" autocmd FileType javascript                                         set omnifunc=javascriptcomplete#CompleteJS
let g:EclimCompletionMethod = 'omnifunc'
autocmd FileType python                                             let b:run_script = '! clear;python3 %'
autocmd FileType python                                             let g:pymode_python = 'python3'
autocmd FileType cpp                                                let b:run_script = '! clear; make && !%:r'
autocmd FileType java                                               nnoremap <C-S-i> :JavaImportOrganize<CR>
inoremap <C-Space> <C-x><C-o>
" autocmd FileType *.c                                              let b:run_script='gcc\ %\ &&\ ./!%:r.out'

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

set timeoutlen=1000 ttimeoutlen=0

" endl but not really
" this is actually not needed since d$
" nnoremap - $h
" vnoremap - $h

" nnoremap F gg=G''

" let g:EclimFileTypeValidate = 0
let g:syntastic_java_javac_config_file_enabled = 1
set encoding=utf-8

colorscheme peachpuff
hi Search ctermbg=1
hi Folded ctermbg=none
hi Pmenu ctermbg=none
hi PmenuSel ctermbg=1
hi Pmenu ctermfg=3
hi SpellBad ctermbg=2
hi ColorColumn ctermbg=3
hi DiffAdd      ctermfg=7          ctermbg=6
hi DiffChange   ctermfg=4          ctermbg=5
hi DiffDelete   ctermfg=2          ctermbg=3
hi DiffText     ctermfg=1          ctermbg=8

" https://github.com/gotbletu/shownotes/blob/master/vim_neovim_manpager.md
" augroup manlaunchtoc
"     autocmd!
"     if has('nvim')
"         autocmd FileType man
"             \ call man#show_toc() |
"             \ setlocal laststatus=0 nonumber norelativenumber |
"             \ nnoremap <buffer> l <Enter> |
"             \ wincmd H |
"             \ vert resize 35 |
"             \ wincmd p
"     endif
" augroup end
set fillchars+=vert:│
" latex snippets
" autocmd FileType   tex        inoremap   <F5>       <Esc>:!xelatex<space><c-r>%<Enter>a
" autocmd FileType   tex        nnoremap   <F5>       :!xelatex<space><c-r>%<Enter>
autocmd FileType tex inoremap pb<Tab> \pagebreak
autocmd FileType tex inoremap fr<Tab> \begin{frame}<CR>\frametitle{}<CR><CR><+><CR><CR>\end{frame}<CR><CR><+><Esc>6kf}i
autocmd FileType tex inoremap fi<Tab> \begin{fitch}<CR><CR>\end{fitch}<CR><CR><+><Esc>3kA
autocmd FileType tex inoremap exe<Tab> \begin{exe}<CR>\ex<Space><CR>\end{exe}<CR><CR><+><Esc>3kA
autocmd FileType tex inoremap em<Tab> \emph{} <+><Esc>T{i
autocmd FileType tex inoremap bf<Tab> \textbf{} <+><Esc>T{i
autocmd FileType tex vnoremap , <ESC>`<i\{<ESC>`>2la}<ESC>?\\{<CR>a
autocmd FileType tex inoremap it<Tab> \textit{} <+><Esc>T{i
autocmd FileType tex vnoremap it xa\textit{}<Esc>P
autocmd FileType tex vnoremap tt xa\texttt{}<Esc>P

autocmd FileType tex inoremap ct<Tab> \textcite{}<+><Esc>T{i
autocmd FileType tex inoremap cp<Tab> \parencite{}<+><Esc>T{i
autocmd FileType tex inoremap co<Tab> \citeonline{}<+><Esc>T{i
autocmd FileType tex inoremap cb<Tab> \citebook{}<+><Esc>T{i

autocmd FileType tex inoremap glos<Tab> {\gll<Space><+><Space>\\<CR><+><Space>\\<CR>\trans{``<+>''}}<Esc>2k2bcw
autocmd FileType tex inoremap x<Tab> \begin{xlist}<CR>\ex<Space><CR>\end{xlist}<Esc>kA<Space>
autocmd FileType tex inoremap ol<Tab> \begin{enumerate}<CR><CR>\end{enumerate}<CR><CR><+><Esc>3kA\item<Space>
autocmd FileType tex inoremap ul<Tab> \begin{itemize}<CR><CR>\end{itemize}<CR><CR><+><Esc>3kA\item<Space>
autocmd FileType tex inoremap li<Tab> <CR>\item<Space>
autocmd FileType tex inoremap ref<Tab> \ref{}<Space><+><Esc>T{i
autocmd FileType tex inoremap tab<Tab> \begin{tabular}<CR><+><CR>\end{tabular}<CR><CR><+><Esc>4kA{}<Esc>i
autocmd FileType tex inoremap ot<Tab> \begin{tableau}<CR>\inp{<+>}<Tab>\const{<+>}<Tab><+><CR><+><CR>\end{tableau}<CR><CR><+><Esc>5kA{}<Esc>i
autocmd FileType tex inoremap can<Tab> \cand{}<Tab><+><Esc>T{i
autocmd FileType tex inoremap con<Tab> \const{}<Tab><+><Esc>T{i
autocmd FileType tex inoremap v<Tab> \vio{}<Tab><+><Esc>T{i
autocmd FileType tex inoremap a<Tab> \href{}{<+>}<Space><+><Esc>2T{i
autocmd FileType tex inoremap sc<Tab> \textsc{}<Space><+><Esc>T{i
autocmd FileType tex inoremap chap<Tab> \chapter{}<CR><CR><+><Esc>2kf}i
autocmd FileType tex inoremap sec<Tab> \section{}<CR><CR><+><Esc>2kf}i
autocmd FileType tex inoremap ssec<Tab> \subsection{}<CR><CR><+><Esc>2kf}i
autocmd FileType tex inoremap sssec<Tab> \subsubsection{}<CR><CR><+><Esc>2kf}i
autocmd FileType tex inoremap st<Tab> <Esc>F{i*<Esc>f}i
autocmd FileType tex inoremap beg<Tab> \begin{DELRN}<CR><+><CR>\end{DELRN}<CR><CR><+><Esc>4k0fR:MultipleCursorsFind<Space>DELRN<CR>c
autocmd FileType tex inoremap up<Tab> <Esc>/usepackage<CR>o\usepackage{}<Esc>i
autocmd FileType tex nnoremap up<Tab> /usepackage<CR>o\usepackage{}<Esc>i
autocmd FileType tex inoremap tt<Tab> \texttt{}<Space><+><Esc>T{i
autocmd FileType tex inoremap bt<Tab> {\blindtext}
autocmd FileType tex inoremap nu<Tab> $\varnothing$
autocmd FileType tex inoremap col<Tab> \begin{columns}[T]<CR>\begin{column}{.5\textwidth}<CR><CR>\end{column}<CR>\begin{column}{.5\textwidth}<CR><+><CR>\end{column}<CR>\end{columns}<Esc>5kA
autocmd FileType tex inoremap rn<Tab> (\ref{})<+><Esc>F}i

set guicursor=i:100-bCursor
set conceallevel=0
set noshowcmd

function! Synctex()
  " remove 'silent' for debugging
  execute "silent !zathura --synctex-forward " . line('.') . ":" . col('.') . ":" . bufname('%') . " " . bufname('%')[:-5]. ".pdf"
  redraw!
endfunction
