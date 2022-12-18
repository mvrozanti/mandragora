let g:goyo_width='85%'
let g:goyo_height='90%'
let g:tmux_navigator_no_mappings = 1
let g:tex_flavor = 'latex'
let vimDir = '$HOME/.vim'
let &runtimepath.=','.vimDir
let g:indentLine_enabled = 0
let g:EclimSignLevel = 'error'
let g:colorizer_auto_color = 1
let g:ycm_key_list_select_completion = ['<TAB>']
let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_auto_start_csharp_server = 1
let g:ycm_auto_stop_csharp_server = 1
let g:ycm_key_list_stop_completion = ['<Enter>']
let g:ycm_filetype_whitelist = {
			\ "cs":1
			\ }
let g:vebugger_leader = '\'
if !exists('g:vdebug_options')
    let g:vdebug_options = {}
endif
let g:vdebug_options.break_on_open = 0
let g:grep_cmd_opts = '--hidden'
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
let NERDTreeIgnore = ['\.pyc$', '\.o$', '\.so$', '\.a$', '\.swp', '*\.swp', '\.swo', '\.swn', '\.swh', '\.swm', '\.swl', '\.swk', '\.sw*$', '[a-zA-Z]*egg[a-zA-Z]*', '[a-zA-Z]*cache[a-zA-Z]*', '.DS_Store']
let g:NERDTreeQuitOnOpen=1
let g:NERDTreeShowHidden=1
let g:NERDTreeWinPos="left"
let g:NERDTreeDirArrows=0
let g:netrw_banner=0
let g:netrw_browse_split=4
let g:netrw_altv=1
let g:netrw_liststyle=3
let g:ctrlp_show_hidden=1
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_quiet_messages = { "regex": [
        \ '\mpossible unwanted space at "{"',
        \ '\Delete this space to maintain correct pagereferences',
        \ 'Wrong length of dash may have been used.'] }
let g:syntastic_cpp_compiler_options = '-std=c++11 -stdlib=libc++'
let g:syntastic_javascript_mri_args = "--config=$HOME/.jshintrc"
let g:syntastic_python_checkers = [ 'pylint', 'flake8', 'pep8', 'pyflakes', 'python3', 'pymode']
let g:syntastic_yaml_checkers = ['jsyaml']
let g:syntastic_html_tidy_exec = 'tidy5'
let g:flake8_show_in_file=1
let g:UltiSnipsExpandTrigger="<A-ENTER>"
let g:UltiSnipsJumpForwardTrigger="<A-ENTER>"
let g:UltiSnipsJumpBackwardTrigger="<A-BACKSPACE>"
let g:UltiSnipsEditSplit="vertical"
let g:BASH_Ctrl_j = 'off'
let g:syntastic_java_javac_config_file_enabled = 1
let g:airline#extensions#tagbar#enabled = 1
let g:airline_powerline_fonts = 1
let g:airline_theme='atomic'
let g:rainbow_active = 1
let g:startify_enable_special = 0
let g:startify_files_number = 5
let g:startify_session_autoload = 1
let g:startify_update_oldfiles = 1
let g:startify_update_oldfiles = 1
let g:startify_lists = [
      \ { 'type': 'dir' },
      \ { 'type': 'files',     'header': []                    },
      \ ]
let g:mkdp_browser = 'firefox'
" let g:mkdp_markdown_css = expand('HOME/css/darkdown.css')
let g:mkdp_highlight_css = expand('$HOME/css/darkdown.css')
let g:coc_disable_startup_warning = 1
let g:python_recommended_style = 1
