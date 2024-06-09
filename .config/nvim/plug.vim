call plug#begin()
Plug 'salsifis/vim-transpose', {'on': 'Transpose'}
Plug 'iberianpig/tig-explorer.vim', {'on': 'TigExplorer'}
Plug 'Yggdroot/indentLine', {'on': 'IndentLinesToggle'}
Plug 'pearofducks/ansible-vim', {'for': 'ansible'}
Plug 'tomtom/tcomment_vim', {'on': 'TComment'}
Plug 'christoomey/vim-tmux-navigator'
Plug 'tpope/vim-surround'
Plug 'lervag/vim-latex', {'for': 'tex'}
Plug 'tpope/vim-commentary'
Plug 'terryma/vim-multiple-cursors', {'on': 'MultipleCursors'}
Plug 'alvan/vim-closetag', {'for': ['html', 'xml']}
Plug 'mogelbrod/vim-jsonpath', {'for': 'json'}
Plug 'itchyny/screensaver.vim'
Plug 'richq/vim-cmake-completion', {'for': 'cmake'}
Plug 'dbmrq/vim-ditto'
Plug 'scrooloose/vim-slumlord'
Plug 'mikelue/vim-maven-plugin'
Plug 'skwp/greplace.vim'
if has('nvim')
  Plug 'neoclide/coc.nvim', {'branch':'release'}
endif
Plug 'tommcdo/vim-exchange'
Plug 'jiangmiao/auto-pairs'
Plug 'godlygeek/tabular', {'on': 'Tabularize'}
Plug 'junegunn/goyo.vim', {'on': 'Goyo'}
Plug 'realincubus/vim-clang-refactor'
Plug 'sakhnik/nvim-gdb', { 'do': ':!./install.sh \| UpdateRemotePlugins', 'on': 'GdbStart' }
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
Plug 'idanarye/vim-vebugger', {'on': 'Vebugger'}
Plug 'sophacles/vim-processing', {'for': 'pde'}
Plug 'scrooloose/nerdtree', {'on': 'NERDTreeToggle'}
Plug 'ryanoasis/vim-devicons'
Plug 'mvrozanti/a.vim', {'for': 'c'}
Plug 'mhinz/vim-startify'
Plug 'mattn/webapi-vim'
Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-fugitive', {'on': 'G'}
Plug 'chrisbra/unicode.vim', {'on': 'UnicodeSearch'}
Plug 'othree/yajs.vim'
Plug 'kien/ctrlp.vim', {'on': 'CtrlP'}
Plug 'danro/rename.vim', {'on': 'Rename'}
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && yarn install', 'for': 'markdown' }
Plug 'vim-scripts/argtextobj.vim'
Plug 'terryma/vim-expand-region'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'majutsushi/tagbar', {'on': 'TagbarToggle'}
Plug 'easymotion/vim-easymotion'
Plug 'vim-scripts/JavaScript-Indent', {'for': 'javascript'}
Plug 'junegunn/rainbow_parentheses.vim'
Plug 'sindrets/diffview.nvim', {'on': 'DiffviewOpen'}
call plug#end()
