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
  highlight Normal       ctermfg=231 ctermbg=234
  highlight LineNr       ctermfg=250 ctermbg=234
  highlight CursorLineNr ctermfg=220 ctermbg=234 cterm=bold

  " popup / menu
  highlight Pmenu        ctermfg=231 ctermbg=236
  highlight PmenuSel     ctermfg=234 ctermbg=250
  highlight Visual       ctermfg=234 ctermbg=237
  highlight Search       ctermfg=234 ctermbg=220

  " strong statusline defaults (light text on colored blocks)
  highlight StatusLine   ctermfg=231 ctermbg=237 cterm=bold
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

