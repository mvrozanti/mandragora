if exists('g:colors_name')
    unlet g:colors_name
endif
let g:colors_name = 'pywal'

let s:wal_file = fnamemodify('~/.cache/wal/colors-wal.vim', ':p')
if filereadable(s:wal_file)
    execute 'source ' . s:wal_file
else
    echo "Pywal colors.vim not found!"
    finish
endif

let s:wal_colors = [
      \ color0, color1, color2, color3, color4, color5, color6, color7,
      \ color8, color9, color10, color11, color12, color13, color14, color15
      \ ]

function! s:hex_luminance(hex) abort
    if a:hex == '' || a:hex[0] !=# '#'
        return 0.0
    endif
    let r = str2nr(strpart(a:hex, 1, 2), 16)
    let g = str2nr(strpart(a:hex, 3, 2), 16)
    let b = str2nr(strpart(a:hex, 5, 2), 16)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
endfunction

let s:light_thresh = 0.60
let s:wal_colors_light = filter(copy(s:wal_colors), 's:hex_luminance(v:val) > s:light_thresh')

function! s:pick_index_from_name(name, count) abort
    let sum = 0
    for n in str2list(a:name)
        let sum += n
    endfor
    return (sum % a:count)
endfunction

function! s:pick_color_for_group(group, colors) abort
    if len(a:colors) == 0
        return a:colors[0]
    endif
    let idx = s:pick_index_from_name(a:group, len(a:colors))
    return a:colors[idx]
endfunction

let s:text_groups = [
      \ 'Normal', 'Comment', 'Identifier', 'Statement', 'Type', 'Function',
      \ 'String', 'Constant', 'Number', 'PreProc', 'Special', 'Conditional',
      \ 'Repeat', 'Operator', 'Label', 'Exception', 'Keyword', 'Todo'
      \ ]

function! s:apply_dynamic_pywal() abort
    let current_mode = mode()
    let in_visual = current_mode ==# 'v' || current_mode ==# 'V' || current_mode ==# "\<C-V>"

    for group in getcompletion('', 'highlight')
        if index(s:text_groups, group) >= 0
            let fg = s:pick_color_for_group(group, s:wal_colors_light)
        else
            let fg = s:pick_color_for_group(group, s:wal_colors)
        endif

        if in_visual
            let bg = '#444444'  " pick a pywal-ish visual background
        else
            let bg = 'NONE'
        endif

        execute 'hi ' . group . ' guifg=' . fg . ' guibg=' . bg
    endfor

    " Ensure message lines are readable
    if len(s:wal_colors_light) > 0
        let msg_fg = s:wal_colors_light[0]
    else
        let msg_fg = '#ffffff'
    endif
    execute 'hi MsgArea guifg=' . msg_fg . ' guibg=NONE'
    execute 'hi ModeMsg guifg=' . msg_fg . ' guibg=NONE'
endfunction

call s:apply_dynamic_pywal()
autocmd ColorScheme * call s:apply_dynamic_pywal()

