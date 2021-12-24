call plug#begin()
Plug 'salsifis/vim-transpose' " Vim plugin - Transpose matrices of text (swap lines with columns). 
Plug 'iberianpig/tig-explorer.vim'
Plug 'Yggdroot/indentLine'
Plug 'pearofducks/ansible-vim'
Plug 'tomtom/tcomment_vim'
Plug 'chrisbra/csv.vim'
Plug 'christoomey/vim-tmux-navigator'
Plug 'tpope/vim-surround'
Plug 'lervag/vim-latex'
Plug 'tpope/vim-commentary'
Plug 'terryma/vim-multiple-cursors'
Plug 'alvan/vim-closetag'
" Vim plugin that lets you navigate JSON documents using dot.notation.paths 
Plug 'mogelbrod/vim-jsonpath'
Plug 'itchyny/screensaver.vim'
Plug 'richq/vim-cmake-completion'
Plug 'dbmrq/vim-ditto'
Plug 'scrooloose/vim-slumlord'
Plug 'mikelue/vim-maven-plugin'
Plug 'skwp/greplace.vim'
if has('nvim')
  Plug 'neoclide/coc.nvim', {'branch':'release'}
endif
Plug 'tommcdo/vim-exchange'
Plug 'jiangmiao/auto-pairs'
Plug 'godlygeek/tabular'
Plug 'junegunn/goyo.vim'
Plug 'realincubus/vim-clang-refactor'
Plug 'sakhnik/nvim-gdb', { 'do': ':!./install.sh \| UpdateRemotePlugins' }
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
Plug 'idanarye/vim-vebugger'
Plug 'sophacles/vim-processing'
Plug 'scrooloose/nerdtree'
Plug 'ryanoasis/vim-devicons'
Plug 'mvrozanti/a.vim'
Plug 'mhinz/vim-startify'
Plug 'mattn/webapi-vim'
Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-fugitive'
Plug 'chrisbra/Colorizer'
Plug 'chrisbra/unicode.vim'
Plug 'othree/yajs.vim'
Plug 'kien/ctrlp.vim'
Plug 'danro/rename.vim'
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app & yarn install'  }
Plug 'vim-scripts/argtextobj.vim'
Plug 'terryma/vim-expand-region'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'majutsushi/tagbar'
Plug 'easymotion/vim-easymotion'
Plug 'vim-scripts/JavaScript-Indent'
Plug 'junegunn/rainbow_parentheses.vim'
" Plug 'tpope/vim-sleuth' " this stuff is dangerous
" Plug 'amerlyq/vim-focus-autocmd'
" Plug 'mvrozanti/bspwm_border_color'
" Plug 'nvie/vim-flake8'
call plug#end()
