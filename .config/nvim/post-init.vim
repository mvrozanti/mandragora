call SetupCommandAlias("jsonify","%!python -m json.tool")
call SetupCommandAlias("pi","PlugInstall")
call SetupCommandAlias("pc","PlugClean")
au FileType python au BufWinEnter set sw=4 sts=4 ts=8
