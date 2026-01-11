call SetupCommandAlias("jsonify","%!python -m json.tool")
call SetupCommandAlias("pi","PlugInstall")
call SetupCommandAlias("pc","PlugClean")
au FileType python au BufWinEnter set sw=4 sts=4 ts=8






augroup force_airline_look
  autocmd!
  autocmd VimEnter,ColorScheme * call s:ApplyAirlineLook()
augroup END

function! s:ApplyAirlineLook() abort
  if exists('+termguicolors')
    set notermguicolors
  endif
  set t_Co=256
  set background=dark

  " core editor
  highlight Normal       ctermfg=231 ctermbg=NONE
  highlight Comment      ctermfg=244 cterm=italic
  highlight Constant     ctermfg=5 
  highlight Identifier   ctermfg=219 
  highlight Statement    ctermfg=218 
  highlight PreProc      ctermfg=214 
  highlight Type         ctermfg=217  
  highlight Special      ctermfg=216  
  highlight Underlined   ctermfg=215  
  highlight Visual       ctermbg=237
  highlight LineNr       ctermfg=250 ctermbg=234
  highlight CursorLineNr ctermfg=220 ctermbg=234 cterm=bold

  " popup / menu
  highlight Pmenu        ctermfg=231 ctermbg=236
  highlight PmenuSel     ctermfg=234 ctermbg=250
  highlight Visual       ctermfg=234 ctermbg=237
  highlight Search       ctermfg=234 ctermbg=220

  " strong statusline defaults (light text on colored blocks)
  highlight StatusLine   ctermfg=231 ctermbg=NONE cterm=bold
  highlight StatusLineNC ctermfg=250 ctermbg=234

  " Airline: force light foreground + contrast backgrounds
  highlight AirlineNormal        ctermfg=231 ctermbg=237 cterm=bold
  highlight AirlineInsert        ctermfg=231 ctermbg=33  cterm=bold
  highlight AirlineVisual        ctermfg=231 ctermbg=136 cterm=bold
  highlight AirlineReplace       ctermfg=231 ctermbg=160 cterm=bold
  highlight AirlineCommand       ctermfg=231 ctermbg=61  cterm=bold
  highlight AirlineReadOnly      ctermfg=231 ctermbg=239 cterm=bold
  highlight AirlineWarning       ctermfg=231 ctermbg=208 cterm=bold
  highlight AirlineError         ctermfg=231 ctermbg=160 cterm=bold
  highlight AirlineGitBranch     ctermfg=231 ctermbg=236
  highlight AirlineGitDiffAdded  ctermfg=231 ctermbg=22
  highlight AirlineGitDiffRemoved ctermfg=231 ctermbg=160
  highlight AirlineGitDiffChanged ctermfg=231 ctermbg=136



let g:airline_section_warning = ''
let g:airline_section_warning_nc = ''



highlight airline_c_to_airline_z guifg=#9a616d guibg=#9a616d ctermfg=238 ctermbg=238
highlight airline_y_to_airline_z guifg=#9a616d guibg=#9a616d ctermfg=238 ctermbg=238
highlight airline_z_to_airline_warning guifg=#9a616d guibg=#9a616d ctermfg=238 ctermbg=238
highlight airline_warning_to_airline_error guifg=#9a616d guibg=#9a616d ctermfg=238 ctermbg=238


highlight AirlineZ guifg=#dd8b9d guibg=#9a616d ctermfg=10 ctermbg=238
highlight airline_a_inactive_bold          cterm=bold gui=bold guifg=#9a616d
highlight airline_a_inactive_red           ctermfg=160 guifg=#ff0000
highlight airline_b_inactive               guifg=#9a616d
highlight airline_b_inactive_bold          cterm=bold gui=bold guifg=#9a616d
highlight airline_b_inactive_red           ctermfg=160 guifg=#ff0000
highlight airline_c_inactive               guifg=#9a616d
highlight airline_c_inactive_bold          cterm=bold gui=bold guifg=#9a616d
highlight airline_c_inactive_red           ctermfg=160 guifg=#ff0000
highlight airline_warning_inactive         ctermfg=232 ctermbg=166 guifg=#000000 guibg=#df5f00
highlight airline_warning_inactive_bold    cterm=bold ctermfg=232 ctermbg=166 gui=bold guifg=#000000 guibg=#df5f00
highlight airline_warning_inactive_red     ctermfg=160 ctermbg=166 guifg=#ff0000 guibg=#df5f00

highlight airline_x                         ctermfg=10 guifg=#dd8b9d
highlight airline_x_bold                    cterm=bold ctermfg=10 gui=bold guifg=#dd8b9d
highlight airline_x_red                     ctermfg=160 guifg=#ff0000
highlight airline_y                         guibg=#9a616d
highlight airline_y_bold                    cterm=bold gui=bold guibg=#9a616d
highlight airline_y_red                     ctermfg=160 guifg=#ff0000 guibg=#9a616d
highlight airline_z                         ctermbg=10 guibg=#dd8b9d
highlight airline_z_bold                    cterm=bold ctermbg=10 gui=bold guibg=#dd8b9d
highlight airline_z_red                     ctermfg=160 ctermbg=10 guifg=#ff0000 guibg=#dd8b9d

highlight airline_term                      ctermfg=85 ctermbg=232 guifg=#9cffd3 guibg=#202020
highlight airline_term_bold                 cterm=bold ctermfg=85 ctermbg=232 gui=bold guifg=#9cffd3 guibg=#202020
highlight airline_term_red                  ctermfg=160 ctermbg=232 guifg=#ff0000 guibg=#202020

highlight airline_error                     ctermfg=232 ctermbg=160 guifg=#000000 guibg=#990000
highlight airline_error_bold                cterm=bold ctermfg=232 ctermbg=160 gui=bold guifg=#000000 guibg=#990000
highlight airline_error_red                 ctermfg=160 ctermbg=160 guifg=#ff0000 guibg=#990000

highlight airline_a                         ctermbg=10 guibg=#dd8b9d
highlight airline_a_bold                    cterm=bold ctermbg=10 gui=bold guibg=#dd8b9d
highlight airline_a_red                     ctermfg=160 ctermbg=10 guifg=#ff0000 guibg=#dd8b9d
highlight airline_b                         guibg=#9a616d
highlight airline_b_bold                    cterm=bold gui=bold guibg=#9a616d
highlight airline_b_red                     ctermfg=160 guifg=#ff0000 guibg=#9a616d
highlight airline_c                         ctermfg=10 guifg=#dd8b9d
highlight airline_c_bold                    cterm=bold ctermfg=10 gui=bold guifg=#dd8b9d
highlight airline_c_red                     ctermfg=160 guifg=#ff0000
highlight airline_warning                   ctermfg=232 ctermbg=166 guifg=#000000 guibg=#df5f00
highlight airline_warning_bold              cterm=bold ctermfg=232 ctermbg=166 gui=bold guifg=#000000 guibg=#df5f00
highlight airline_warning_red               ctermfg=160 ctermbg=166 guifg=#ff0000 guibg=#df5f00

highlight airline_a_to_airline_b            ctermfg=10 guifg=#dd8b9d guibg=#9a616d
highlight airline_b_to_airline_c            guifg=#9a616d
highlight airline_c_to_airline_x            ctermfg=10 guifg=#dd8b9d guibg=#9a616d
highlight airline_x_to_airline_y            guifg=#9a616d
highlight airline_y_to_airline_z            ctermfg=10 guifg=#dd8b9d guibg=#9a616d
highlight airline_z_to_airline_warning      ctermfg=166 ctermbg=10 guifg=#df5f00 guibg=#dd8b9d
highlight airline_warning_to_airline_error ctermfg=160 ctermbg=166 guifg=#990000 guibg=#df5f00











  " compatibility links (some themes use these)
  highlight airline_a ctermfg=231 ctermbg=237 cterm=bold
  highlight airline_b ctermfg=231 ctermbg=236
  highlight airline_c ctermfg=231 ctermbg=234
  highlight airline_sep ctermfg=236 ctermbg=237

  " fallback links for StatusLine groups airline might use
  highlight LinkStatusLine   ctermfg=231 ctermbg=237
  highlight TabLineFill      ctermfg=250 ctermbg=234
  highlight TabLineSel       ctermfg=231 ctermbg=237

  " make sure airline redraws with new highlights
  if exists(':AirlineRefresh')
    silent! AirlineRefresh
  endif
endfunction

command! ForceAirlineLook call s:ApplyAirlineLook()

autocmd VimEnter * let g:airline_symbols['executable'] = '🔥' | AirlineRefresh

augroup MyAirlineOverrides
  autocmd!
  autocmd VimEnter * ++once call MyAirline_Setup()
augroup END

function! MyAirline_Setup() abort
  " ensure symbols dict exists and change executable icon
  if !exists('g:airline_symbols') | let g:airline_symbols = {} | endif
  let g:airline_symbols['executable'] = ''

  " Rightmost compact position section
  let g:airline_section_z = '%p%% %l:%c'

  " --- helpers (GLOBAL functions so %{...} can call them) ---

  " filetype icon
  function! MyAirline_GetFileIcon() abort
      let l:ext = expand('%:e')

      " directories (netrw, oil, etc.)
      if &buftype ==# 'nofile' || &filetype ==# 'netrw'
          return ''
      endif

      " executables
      if executable(expand('%:p'))
          return ''
      endif

      " archives
      if l:ext =~? '^\(zip\|tar\|gz\|xz\|7z\|rar\)$'
          return ''
      endif

      " images / video
      if l:ext =~? '^\(jpg\|jpeg\|png\|gif\|webp\|bmp\|tiff\|mp4\|mkv\|avi\|mov\|webm\)$'
          return ''
      endif

      " audio
      if l:ext =~? '^\(mp3\|flac\|wav\|ogg\|m4a\)$'
          return ''
      endif

      " code
      if l:ext ==# 'c' || l:ext ==# 'h'
          return ''
      elseif l:ext ==# 'cpp'
          return ''
      elseif l:ext ==# 'rs'
          return ''
      elseif l:ext ==# 'go'
          return ''
      elseif l:ext ==# 'py'
          return ''
      elseif l:ext ==# 'js'
          return ''
      elseif l:ext ==# 'ts'
          return ''
      elseif l:ext ==# 'sh'
          return ''
      elseif l:ext ==# 'lua'
          return ''
      elseif l:ext ==# 'java'
          return ''
      elseif l:ext ==# 'kt'
          return ''
      elseif l:ext ==# 'html' || l:ext ==# 'xhtml'
          return ''
      endif

      " config / data
      if l:ext =~? '^\(json\|yaml\|yml\|toml\|ini\|conf\)$'
          return ''
      endif

      " docs
      if l:ext ==# 'md'
          return ''
      elseif l:ext ==# 'txt'
          return ''
      elseif l:ext ==# 'pdf'
          return ''
      elseif l:ext ==# 'epub'
          return ''
      endif

      " disk images
      if l:ext =~? '^\(iso\|img\|bin\)$'
          return ''
      endif

      " symlink
      if getftype(expand('%:p')) ==# 'link'
          return ''
      endif

      " fallback file
      return ''
  endfunction

  " git branch + dirty flag (prefer fugitive if available)
  function! MyAirline_GetGitBranch() abort
    if exists('*fugitive#head')
      let l:branch = fugitive#head()
      if empty(l:branch)
        return ''
      endif
      let l:dirty = &modified ? '⚡' : ''
      return l:branch . l:dirty
    endif

    " Fallback: try a cheap git check (avoid calling in non-git dirs)
    if stridx(system('git rev-parse --is-inside-work-tree 2>/dev/null'), 'true') >= 0
      let l = substitute(system('git rev-parse --abbrev-ref HEAD 2>/dev/null'), '\n', '', 'g')
      if empty(l) | return '' | endif
      let ldirty = &modified ? '⚡' : ''
      return l . ldirty
    endif

    return ''
  endfunction

  " LSP / diagnostics summary:
  " - If using coc.nvim, use coc#status()
  " - If using Neovim builtin LSP, use luaeval diagnostic counts
  function! MyAirline_GetLSPStatus() abort
    " coc.nvim
    if exists('*coc#status')
      return substitute(coc#status(), '\n', ' ', 'g')
    endif

    " Neovim builtin LSP (uses luaeval; only works in nvim)
    if has('nvim')
      try
        let errors = luaeval('vim.lsp.diagnostic.get_count(0, "Error")')
        let warns  = luaeval('vim.lsp.diagnostic.get_count(0, "Warning")')
        if (errors == 0 && warns == 0)
          return ''
        endif
        return printf('E:%d W:%d', errors, warns)
      catch
        return ''
      endtry
    endif

    return ''
  endfunction

  " --- set the section C using the functions above ---
  " note: %{Func()} is evaluated by statusline
  let g:airline_section_c = '%{MyAirline_GetFileIcon()} %{MyAirline_GetGitBranch()} %{MyAirline_GetLSPStatus()}'

  " redraw airline to apply changes immediately
  silent! AirlineRefresh
endfunction

