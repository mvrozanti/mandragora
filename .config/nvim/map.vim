nn <Space><Space> <Esc>/<+><CR>"_3x:noh<CR>i
map <A-F> mzgg=G`zzz
nor <C-_> /\V
map / /\c
nn < <<
nn > >>
vn / y/<C-r><C-w><CR>
vn p "_dP
vn ? y:%s/<C-r><C-w>//gn<CR>
nn <A-p> o<A-p>
map Q <NOP>
nn <A-m> :tabe %<CR>
ino <A-Backspace> <A-c>iw
nn <A-Backspace> viwd
ino <C-v> <Esc>pa
ino jk <Esc>l
ino jK <Esc>l
ino Jk <Esc>l
ino JK <Esc>l
vn JK <Esc>
ino QQ <Esc>:q!<CR>
nn QQ :q!<CR>
nn <A-J> :resize -2<CR>
nn <A-K> :resize +2<CR>
nn <A-H> :vertical resize +2<CR>
nn <A-L> :vertical resize -2<CR>
ino <Insert> <Esc>
au FileType prolog ino she<tab> #!/usr/bin/swipl -q
au FileType wolframlanguage ino she<tab> #!/usr/bin/wolframscript -file
au FileType make ino al<tab> all:<CR>
vmap <C-Space> gc
nmap <C-Space> gcc
nmap S ysiw

noremap <silent> <c-h> <Cmd>TmuxNavigateLeft<cr>
noremap <silent> <c-j> <Cmd>TmuxNavigateDown<cr>
noremap <silent> <c-k> <Cmd>TmuxNavigateUp<cr>
noremap <silent> <c-l> <Cmd>TmuxNavigateRight<cr>
noremap <silent> <c-\> <Cmd>TmuxNavigatePrevious<cr>

nn <A-h> :<C-U>TmuxNavigateLeft<cr>
nn <A-j> :<C-U>TmuxNavigateDown<cr>
nn <A-k> :<C-U>TmuxNavigateUp<cr>
nn <A-l> :<C-U>TmuxNavigateRight<cr>
nn <A-Left>  :TmuxNavigateLeft<cr>
nn <A-Down>  :TmuxNavigateDown<cr>
nn <A-Up>    :TmuxNavigateUp<cr>
nn <A-Right> :TmuxNavigateRight<cr>
nn yD y$
nn <A-i> f(a
ino <A-i> <Esc>f(a
nn <A-I> <Esc>f,a
ino <A-I> <Esc>f,a
vn <C-f> y/<C-R>"<CR>
nn <CR> i<CR><Esc>
vn ( <Esc>a)<Esc>gvo<Esc>i(<Esc>i
nn yF maggyG'a
nn ZZ <Esc>?<+><CR>"_3xi
nn dl v$hxJhv0w"_x
nn c_ ct_
nn dA F(vbdf)xB
nmap dS bysw<Space><Space>ds)
vn - $h
nn <C-u> 'x
vn <CR> c<CR>
nn <C-Tab> gK
map <F2> :Goyo 200x200<CR>
vn <C-r> "hy:.,$s/<C-r>h//gc<left><left><left>
vn <C-h> "hy:%s/<C-r>h//gc<left><left><left>
" function! ReplaceVisualSelection()
"   let selection = expand('<cword>')
"   let replacement = input('Replace "'.selection.'" with: ')
"   execute 'normal! c'.replacement
" endfunction
" vn <C-h> :echo test<CR>
vn D "hy:%g!/<C-r>h/d"
nn <Del> "_<Del>
nn x "_x
ino she<tab> #!/bin/bash<Esc>o
ino re<tab> return<Space>
ino fori<tab> for(int i=0; i < ; i++){<CR>}<Esc>3Bla
ino forj<tab> for(int j=0; j < ; j++){<CR>}<Esc>3Bla
au FileType javascript ino repl<tab> require('repl').start('> ').context.<+> = <+>;<Esc>
au FileType javascript ino tr<tab> true
au FileType javascript ino fa<tab> false
au FileType javascript ino fori<tab> for(i=0; i < ; i++){<CR>}<Esc>3Bla
au FileType javascript ino wh<tab> while(){<CR><Tab><+><CR>}<Esc>2kf(a
au FileType typescript,html,javascript,p5js ino cl<tab> console.log()<Esc>i
au FileType typescript,html,javascript,p5js ino ok<tab> Object.keys()<Esc>i
au FileType html,javascript,p5js ino fn<tab> function(){<CR><Tab><+><CR>}<Esc>2kf(a
au FileType javascript ino she<tab> #!/usr/bin/env node
au FileType typescript ino im<tab> import<Space>
au FileType cs ino pr<tab> private<Space>
au FileType cs ino psvm<tab> public static void Main(string[] args)<CR>{<CR>}
au FileType cs ino ns<tab> namespace<Space><CR>{<CR>}
au FileType cs ino us<tab> using<Space>
au FileType cs ino pu<tab> public<Space>
au FileType cs ino fa<tab> false
au FileType cs ino tr<tab> true
au FileType cs ino cw<tab> Console.WriteLine()<Esc>i
au FileType java ino psvm<tab> public static void main(String args[]){<CR>}
au FileType java map <silent> <F6> :mvnexec<CR><CR>
au FileType java ino <c-space> <c-x><c-u>
au FileType java ino pr<tab> private<Space>
au FileType java ino pu<tab> public<Space>
au FileType java ino sout<tab> System.out.println()<Esc>i
au FileType java ino fa<tab> false
au FileType java ino tr<tab> true
au FileType java ino st<tab> static<Space>
au FileType python ino ii<tab> isinstance()<Esc>i
au FileType python ino ty<tab> type()<Esc>i
au FileType python ino sir<tab> sys.stdin.read()
au FileType python ino im<tab> import<Space>
au FileType python ino pte<tab> import ptpython; ptpython.embed(globals(), locals())
au FileType python ino pdbt<tab> pdb.set_trace()<Esc>
au FileType python ino fori<tab> for <+> in<Space>
au FileType python ino ld<tab> LOG.debug()<Esc>i
au FileType python ino pr<tab> print()<Esc>i
au FileType python ino dis<tab> def __init__(self, ):<CR><+><Esc>kWi
au FileType python ino inm<tab> if __name__ == '__main__':<CR>
au FileType python ino she<tab> #!/usr/bin/env python
au FileType python ino Fa<tab> False
au FileType python ino Tr<tab> True
au FileType python ino wh<tab> while :<Esc>i
au FileType python ino en<tab> enumerate
au FileType python ino tc<tab> try:<CR><+><CR>except Exception as e: print(e)
au FileType python ino agp<tab> parser = argparse.ArgumentParser(description='<+>')<CR>parsed = parser.parse_args()<CR><+>
au FileType c,cpp,lex ino st<tab> static 
au FileType c,cpp,lex nn <A-e> :VBGevalWordUnderCursor
au FileType c,cpp,lex ino psvm<tab> int main(int argc, char **argv){}<Esc>i<CR><Esc>O
au FileType c,cpp,lex ino uns<tab> using namespace std;<CR>
au FileType c,cpp,lex ino in<tab> #include<><Esc>i
au FileType c,lex ino so<tab> sizeof()<Esc>i
au FileType c,cpp,lex ino pr<tab> printf("\n", <+>);<Esc>9hi
au FileType c,cpp,lex ino fn<tab> <+> <+>(<+>){<CR>}<Esc>O
au FileType c,cpp,java,lex ino sw<tab> switch(){<CR>case <+>:<CR>break;<CR>}<Esc>3kwa
au FileType c,cpp,java,lex ino wh<tab> while(){<CR>}<Esc>kwa
au FileType c,cpp,java,lex ino if<tab> if(){<CR>}<Esc>kwa
nn <silent> <Esc><Esc> :noh<CR>
nn gJ gT
nn gK gt
nn <C-N> :tabe<CR>
nn [ <C-W>
nn , `
nn ' `
ino <C-E> <Esc> "_ddi
nn <C-E> "_dd
vn <C-E> "_d
nn <C-A-h>      :5winc <<CR>
nn <C-A-b>      :5winc +<CR>
nn <C-A-l>      :5winc ><CR>
nn <C-A-u>      :5winc -<CR>
nmap <silent> <leader>w <Plug>(coc-diagnostic-next)

ino <silent><expr> <C-Space>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()

ino <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
ino <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
nn <A-r> :call CocAction('rename')<CR>

function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

nn <F5>   :VBGcontinue<CR>
au FileType c,cpp  nn <F6>   :VBGstartGDB %:r<CR>
au FileType python nn <F6>   :VBGstartPDB3 %<CR>
nn <F7>   :VBGstepIn<CR>
nn <F8>   :VBGstepOver<CR>
nn <C-F8> :VBGtoggleBreakpointThisLine<CR>
nn <F10>  :VBGstepOut<CR>
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
ino <A-Left> <ESC>h
ino <A-Down> <ESC>j
ino <A-Up> <ESC>k
ino <A-Right> <ESC>l
nn <C-W> :call Killit()<CR>
ino <C-W> <Esc>:call Killit()<CR>
" nn <C-W> <Esc>:q<CR>
" ino <C-W> <Esc>:q<CR>
nn <C-S> <Esc>:w<CR>
ino <C-S> <Esc>:w<CR>
nn _ :split<CR>
vn _ :split<CR>
nn \| :vsplit<CR>
vn \| :vsplit<CR>
" nn - $h
" vn - $h
" nn F gg=G''
"             \ nn <buffer> l <Enter> |
" au FileType   tex        ino   <F5>       <Esc>:!xelatex<space><c-r>%<Enter>a
" au FileType   tex        nn   <F5>       :!xelatex<space><c-r>%<Enter>
au FileType tex ino pb<Tab> \pagebreak
au FileType tex ino fr<Tab> \begin{frame}<CR>\frametitle{}<CR><CR><+><CR><CR>\end{frame}<CR><CR><+><Esc>6kf}i
au FileType tex ino fi<Tab> \begin{fitch}<CR><CR>\end{fitch}<CR><CR><+><Esc>3kA
au FileType tex ino exe<Tab> \begin{exe}<CR>\ex<Space><CR>\end{exe}<CR><CR><+><Esc>3kA
au FileType tex ino em<Tab> \emph{} <+><Esc>T{i
au FileType tex ino bf<Tab> \textbf{} <+><Esc>T{i
au FileType tex vn , <ESC>`<i\{<ESC>`>2la}<ESC>?\\{<CR>a
au FileType tex ino it<Tab> \textit{} <+><Esc>T{i
au FileType tex vn it xa\textit{}<Esc>P
au FileType tex vn tt xa\texttt{}<Esc>P
au FileType tex ino ct<Tab> \textcite{}<+><Esc>T{i
au FileType tex ino cp<Tab> \parencite{}<+><Esc>T{i
au FileType tex ino co<Tab> \citeonline{}<+><Esc>T{i
au FileType tex ino cb<Tab> \citebook{}<+><Esc>T{i
au FileType tex ino glos<Tab> {\gll<Space><+><Space>\\<CR><+><Space>\\<CR>\trans{``<+>''}}<Esc>2k2bcw
au FileType tex ino x<Tab> \begin{xlist}<CR>\ex<Space><CR>\end{xlist}<Esc>kA<Space>
au FileType tex ino ol<Tab> \begin{enumerate}<CR><CR>\end{enumerate}<CR><CR><+><Esc>3kA\item<Space>
au FileType tex ino item<Tab> \begin{itemize}<CR><CR>\end{itemize}<CR><CR><+><Esc>3kA\item<Space>
au FileType tex ino li<Tab> <CR>\item<Space>
au FileType tex ino ref<Tab> \ref{}<Space><+><Esc>T{i
au FileType tex ino tab<Tab> \begin{tabular}<CR><+><CR>\end{tabular}<CR><CR><+><Esc>4kA{}<Esc>i
au FileType tex ino ot<Tab> \begin{tableau}<CR>\inp{<+>}<Tab>\const{<+>}<Tab><+><CR><+><CR>\end{tableau}<CR><CR><+><Esc>5kA{}<Esc>i
au FileType tex ino can<Tab> \cand{}<Tab><+><Esc>T{i
au FileType tex ino con<Tab> \const{}<Tab><+><Esc>T{i
au FileType tex ino v<Tab> \vio{}<Tab><+><Esc>T{i
au FileType tex ino a<Tab> \href{}{<+>}<Space><+><Esc>2T{i
au FileType tex ino sc<Tab> \textsc{}<Space><+><Esc>T{i
au FileType tex ino chap<Tab> \chapter{}<CR><CR><+><Esc>2kf}i
au FileType tex ino sec<Tab> \section{}<CR><CR><+><Esc>2kf}i
au FileType tex ino ssec<Tab> \subsection{}<CR><CR><+><Esc>2kf}i
au FileType tex ino sssec<Tab> \subsubsection{}<CR><CR><+><Esc>2kf}i
au FileType tex ino st<Tab> <Esc>F{i*<Esc>f}i
au FileType tex ino beg<Tab> \begin{DELRN}<CR><+><CR>\end{DELRN}<CR><CR><+><Esc>4k0fR:MultipleCursorsFind<Space>DELRN<CR>c
au FileType tex ino up<Tab> <Esc>/usepackage<CR>o\usepackage{}<Esc>i
au FileType tex nn up<Tab> /usepackage<CR>o\usepackage{}<Esc>i
au FileType tex ino tt<Tab> \texttt{}<Space><+><Esc>T{i
au FileType tex ino bt<Tab> {\blindtext}
au FileType tex ino nu<Tab> $\varnothing$
au FileType tex ino col<Tab> \begin{columns}[T]<CR>\begin{column}{.5\textwidth}<CR><CR>\end{column}<CR>\begin{column}{.5\textwidth}<CR><+><CR>\end{column}<CR>\end{columns}<Esc>5kA
au FileType tex ino rn<Tab> (\ref{})<+><Esc>F}i
nmap <C-i> :CocAction<CR>
map <C-a> mz<ESC>ggVGy<ESC>'z

nn / /\c
cno %s/ %smagic/
cno \>s/ \>smagic/
nn :g/ :g/\v
nn :g// :g//
map <F3> :echo "hi<" . synIDattr(synID(line("."),col("."),1),"name") . '> trans<' . synIDattr(synID(line("."),col("."),0),"name") . "> lo<" . synIDattr(synIDtrans(synID(line("."),col("."),1)),"name") . ">"<CR>
" ino <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
vmap A :%norm A
