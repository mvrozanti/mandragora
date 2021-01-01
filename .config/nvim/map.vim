map <A-F> mzgg=G`zzz
map / /\c
nnoremap < <<
nnoremap > >>
vnoremap / y/<C-r><C-w><CR>
vnoremap p "_dP
vnoremap ? y:%s/<C-r><C-w>//gn<CR>
nnoremap <A-p> o<A-p>
map Q <NOP>
imap silent <C-h> <A-b>
imap silent <C-l> <A-w>
imap silent <C-Left> <A-b>
imap silent <C-Right> <A-w>
nnoremap <A-m> :tabe %<CR>
inoremap <A-Backspace> <A-c>iw
nnoremap <A-Backspace> viwd
inoremap jk <Esc>l
inoremap jK <Esc>l
inoremap Jk <Esc>l
inoremap JK <Esc>l
vnoremap JK <Esc>
inoremap QQ <Esc>:q!<CR>
nnoremap QQ :q!<CR>
nnoremap <A-J> :resize -2<CR>
nnoremap <A-K> :resize +2<CR>
nnoremap <A-H> :vertical resize +2<CR>
nnoremap <A-L> :vertical resize -2<CR>
inoremap <Insert> <Esc>
autocmd FileType prolog inoremap she<tab> #!/usr/bin/swipl -q
autocmd FileType wolframlanguage inoremap she<tab> #!/usr/bin/wolframscript -file
autocmd FileType make inoremap al<tab> all:<CR>
vmap <C-Space> gc
nmap <C-Space> gcc
nmap S ysiw
let g:tmux_navigator_no_mappings = 0
nnoremap <A-Left>  :TmuxNavigateLeft<cr>
nnoremap <A-Down>  :TmuxNavigateDown<cr>
nnoremap <A-Up>    :TmuxNavigateUp<cr>
nnoremap <A-Right> :TmuxNavigateRight<cr>
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
nnoremap <C-u> 'x
inoremap {<CR> {<CR>}<Esc>k$o
vnoremap <CR> c<CR>
nnoremap <C-Tab> gK
map <F2> :Goyo 200x200<CR>
vnoremap <C-r> "hy:.,$s/<C-r>h//gc<left><left><left>
vnoremap <C-h> "hy:%s/<C-r>h//gc<left><left><left>
vnoremap D "hy:%g!/<C-r>h/d"
nnoremap <Del> "_<Del>
nnoremap x "_x
inoremap she<tab> #!/bin/bash<Esc>o
inoremap re<tab> return<Space>
inoremap fori<tab> for(int i=0; i < ; i++){<CR>}<Esc>3Bla
inoremap forj<tab> for(int j=0; j < ; j++){<CR>}<Esc>3Bla
autocmd FileType javascript inoremap repl<tab> require('repl').start('> ').context.<+> = <+>;<Esc>
autocmd FileType javascript inoremap tr<tab> true
autocmd FileType javascript inoremap fa<tab> false
autocmd FileType javascript inoremap fori<tab> for(i=0; i < ; i++){<CR>}<Esc>3Bla
autocmd FileType javascript inoremap wh<tab> while(){<CR><Tab><+><CR>}<Esc>2kf(a
autocmd FileType typescript,html,javascript inoremap cl<tab> console.log()<Esc>i
autocmd FileType typescript,html,javascript inoremap ok<tab> Object.keys()<Esc>i
autocmd FileType html,javascript inoremap fn<tab> function(){<CR><Tab><+><CR>}<Esc>2kf(a
autocmd FileType javascript inoremap she<tab> #!/usr/bin/env node
autocmd FileType typescript inoremap im<tab> import<Space>
autocmd FileType cs inoremap pr<tab> private<Space>
autocmd FileType cs inoremap psvm<tab> public static void Main(string[] args)<CR>{<CR>}
autocmd FileType cs inoremap ns<tab> namespace<Space><CR>{<CR>}
autocmd FileType cs inoremap us<tab> using<Space>
autocmd FileType cs inoremap pu<tab> public<Space>
autocmd FileType cs inoremap fa<tab> false
autocmd FileType cs inoremap tr<tab> true
autocmd FileType cs inoremap cw<tab> Console.WriteLine()<Esc>i
autocmd FileType java inoremap psvm<tab> public static void main(String args[]){<CR>}
autocmd FileType java map <silent> <F6> :mvnexec<CR><CR>
autocmd FileType java inoremap <c-space> <c-x><c-u>
autocmd FileType java inoremap pr<tab> private<Space>
autocmd FileType java inoremap pu<tab> public<Space>
autocmd FileType java inoremap sout<tab> System.out.println()<Esc>i
autocmd FileType java inoremap fa<tab> false
autocmd FileType java inoremap tr<tab> true
autocmd FileType java inoremap st<tab> static<Space>
autocmd FileType python inoremap ii<tab> isinstance()<Esc>i
autocmd FileType python inoremap im<tab> import<Space>
autocmd FileType python inoremap ci<tab> code.interact(banner='', local=globals().update(locals()) or globals(), exitmsg='')<Esc>
autocmd FileType python inoremap enci<tab> curses.endwin() or code.interact(local=globals().update(locals()) or globals())<Esc>
autocmd FileType python inoremap pdbt<tab> pdb.set_trace()<Esc>
autocmd FileType python inoremap fori<tab> for <+> in<Space>
autocmd FileType python inoremap ld<tab> LOG.debug()<Esc>i
autocmd FileType python inoremap pr<tab> print()<Esc>i
autocmd FileType python inoremap dis<tab> def __init__(self, ):<CR><+><Esc>kWi
autocmd FileType python inoremap inm<tab> if __name__ == '__main__':<CR>
autocmd FileType python inoremap she<tab> #!/usr/bin/env python
autocmd FileType python inoremap Fa<tab> False
autocmd FileType python inoremap Tr<tab> True
autocmd FileType python inoremap wh<tab> while :<Esc>i
autocmd FileType python inoremap en<tab> enumerate
autocmd FileType python inoremap tc<tab> try:<CR><+><CR>except Exception as e: print(e)
autocmd FileType python inoremap agp<tab> parser = argparse.ArgumentParser(description='<+>')<CR>parsed = parser.parse_args()<CR><+>
autocmd FileType c,cpp,lex inoremap st<tab> static 
autocmd FileType c,cpp,lex nnoremap <A-e> :VBGevalWordUnderCursor
autocmd FileType c,cpp,lex inoremap psvm<tab> int main(int argc, char **argv){}<Esc>i<CR><Esc>O
autocmd FileType c,cpp,lex inoremap uns<tab> using namespace std;<CR>
autocmd FileType c,cpp,lex inoremap in<tab> #include<><Esc>i
autocmd FileType c,lex inoremap so<tab> sizeof()<Esc>i
autocmd FileType c,cpp,lex inoremap pr<tab> printf("\n", <+>);<Esc>9hi
autocmd FileType c,cpp,lex inoremap fn<tab> <+> <+>(<+>){<CR>}<Esc>O
autocmd FileType c,cpp,java,lex inoremap sw<tab> switch(){<CR>case <+>:<CR>break;<CR>}<Esc>3kwa
autocmd FileType c,cpp,java,lex inoremap wh<tab> while(){<CR>}<Esc>kwa
autocmd FileType c,cpp,java,lex inoremap if<tab> if(){<CR>}<Esc>kwa
nnoremap <Esc><Esc> :noh<CR>
nnoremap gJ gT
nnoremap gK gt
nnoremap <C-N> :tabe<CR>
nnoremap [ <C-W>
nnoremap , `
nnoremap ' `
inoremap <C-E> <Esc> "_ddi
nnoremap <C-E> "_dd
vnoremap <C-E> "_d
nnoremap <C-A-h>      :5winc <<CR>
nnoremap <C-A-b>      :5winc +<CR>
nnoremap <C-A-l>      :5winc ><CR>
nnoremap <C-A-u>      :5winc -<CR>
" Plug 'severin-lemaignan/vim-minimap'
" autocmd BufEnter * :Minimap
noremap <silent> <c-u> :call smooth_scroll#up   ( &scroll, 10, 2)<CR>
noremap <silent> <c-d> :call smooth_scroll#down ( &scroll, 10, 2)<CR>
noremap <silent> <c-b> :call smooth_scroll#up   ( &scroll*2, 10, 4)<CR>
noremap <silent> <c-f> :call smooth_scroll#down ( &scroll*2, 10, 4)<CR>
nmap <silent> <leader>w <Plug>(coc-diagnostic-next)
inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<cr>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
nnoremap <A-r> :call CocAction('rename')<CR>

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction
inoremap <silent><expr> <c-space>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
nnoremap <F5>   :VBGcontinue<CR>
autocmd FileType c,cpp  nnoremap <F6>   :VBGstartGDB %:r<CR>
autocmd FileType python nnoremap <F6>   :VBGstartPDB3 %<CR>
nnoremap <F7>   :VBGstepIn<CR>
nnoremap <F8>   :VBGstepOver<CR>
nnoremap <C-F8> :VBGtoggleBreakpointThisLine<CR>
nnoremap <F10>  :VBGstepOut<CR>
map <C-t> :NERDTreeToggle<CR>
map ; <Plug>(expand_region_expand)
map + <Plug>(expand_region_shrink)
" nmap <A-f> <Plug>(easymotion-s)
" let g:EasyMotion_do_mapping = 0
" nmap f <Plug>(easymotion-s)
nmap <silent> <A-Up> :wincmd k<CR>
nmap <silent> <A-Down> :wincmd j<CR>
nmap <silent> <A-Left> :wincmd h<CR>
nmap <silent> <A-Right> :wincmd l<CR>
" inoremap <C-Space> <C-x><C-o>
inoremap <A-Left> <ESC>h
inoremap <A-Down> <ESC>j
inoremap <A-Up> <ESC>k
inoremap <A-Right> <ESC>l
nnoremap <C-W> :call Killit()<CR>
inoremap <C-W> <Esc>:call Killit()<CR>
" nnoremap <C-W> <Esc>:q<CR>
" inoremap <C-W> <Esc>:q<CR>
nnoremap <C-S> <Esc>:w<CR>
inoremap <C-S> <Esc>:w<CR>
nnoremap _ :split<CR>
vnoremap _ :split<CR>
nnoremap \| :vsplit<CR>
vnoremap \| :vsplit<CR>
" nnoremap - $h
" vnoremap - $h
" nnoremap F gg=G''
"             \ nnoremap <buffer> l <Enter> |
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
autocmd FileType tex inoremap item<Tab> \begin{itemize}<CR><CR>\end{itemize}<CR><CR><+><Esc>3kA\item<Space>
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
nmap <C-i> :CocAction<CR>
map <C-a> mz<ESC>ggVGy<ESC>'z

" very magic sector https://vim.fandom.com/wiki/Simplifying_regular_expressions_using_magic_and_no-magic
" nnoremap / /\v\c
" vnoremap / /\v\c
nnoremap / /\c
vnoremap / /\c
cnoremap %s/ %smagic/
cnoremap \>s/ \>smagic/
nnoremap :g/ :g/\v
nnoremap :g// :g//
