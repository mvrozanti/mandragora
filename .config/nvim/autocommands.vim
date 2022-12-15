au BufWritePost *.tex silent! !pdflatex % ; pdflatex -synctex=1 % 
au BufWritePost *.bib silent! !bibtex %:r ; pdflatex %:r.tex ; pdflatex -synctex=1 %:r.tex 
au FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
au BufEnter *.pro :setlocal filetype=prolog
au BufEnter *.p5 :setlocal filetype=javascript
au BufEnter *.kt :setlocal filetype=kotlin
au BufEnter *.wl :setlocal filetype=wolframlanguage
au BufEnter *polybar/config :setlocal filetype=polybar
au FileType prolog setlocal commentstring=%\ %s
au FileType polybar setlocal commentstring=\;\ %s
au FileType perl setlocal commentstring=%\ %s
au FileType jq setlocal commentstring=#\ %s
au FileType perl setlocal commentstring=%\ %s
au FileType java call SetupCommandAlias("mvnexec","!mvnexec %")
au FileType java call SetupCommandAlias("PP!","ProjectProblems!")
au FileType python set makeprg=python\ %
au FileType c TagbarToggle
" au BufEnter *.js execute "silent! CocDisable"
au FileType javascript                                         let b:run_script = '!clear;xvkbd -window Firefox -text "\Cr" && xdotool keydown alt key Tab; sleep 2.001; xdotool keyup alt'
au FileType python                                             let b:run_script = '! clear;python3 %'
au FileType python                                             let g:pymode_python = 'python3'
au FileType cpp                                                let b:run_script = '! clear; make && !%:r'
au FileType tex DittoOn
au FileType sh set colorcolumn=120
