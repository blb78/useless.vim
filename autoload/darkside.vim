if exists('g:loaded_darkside')
	finish
endif
let g:loaded_darkside = 1
let s:invalid_coefficient = 'Invalid coefficient. Expected: 0.0 ~ 1.0'
let s:darkside_coeff = get(g:,'darkside_coeff', 0.5)
let s:darkside_bop = get(g:, 'darkside_bop', '^\s*$\n\zs')
let s:darkside_eop = get(g:, 'darkside_eop', '^\s*$')
let s:ignored_files = get(g:,'darkside_ignored_files',[])

let s:cpo_save = &cpo
set cpo&vim


function! s:hex2rgb(str)
	let str = substitute(a:str, '^#', '', '')
	return [eval('0x'.str[0:1]), eval('0x'.str[2:3]), eval('0x'.str[4:5])]
endfunction

let s:gray_converter = {
			\ 0:   231,
			\ 7:   254,
			\ 15:  256,
			\ 16:  231,
			\ 231: 256
			\ }

function! s:gray_contiguous(col)
	let val = get(s:gray_converter, a:col, a:col)
	if val < 231 || val > 256
		throw s:unsupported()
	endif
	return val
endfunction

function! s:gray_ansi(col)
	return a:col == 231 ? 0 : (a:col == 256 ? 231 : a:col)
endfunction

function! s:coeff(coeff)
	let coeff = a:coeff < 0 ? s:darkside_coeff : a:coeff
	if coeff < 0 || coeff > 1
		throw 'Invalid g:darkside_coefficient. Expected: 0.0 ~ 1.0'
	endif
	return coeff
endfunction

function! s:error(msg)
	echohl ErrorMsg
	echo a:msg
	echohl None
endfunction

function! s:dim(coeff)
	let synid = synIDtrans(hlID('Normal'))
	let fg = synIDattr(synid, 'fg#')
	let bg = synIDattr(synid, 'bg#')

	if has('gui_running') || has('termguicolors') && &termguicolors || has('nvim') && $NVIM_TUI_ENABLE_TRUE_COLOR
		if a:coeff < 0 && exists('g:darkside_conceal_guifg')
			let dim = g:darkside_conceal_guifg
		elseif empty(fg) || empty(bg)
			throw s:unsupported()
		else
			let coeff = s:coeff(a:coeff)
			let fg_rgb = s:hex2rgb(fg)
			let bg_rgb = s:hex2rgb(bg)
			let dim_rgb = [
						\ bg_rgb[0] * coeff + fg_rgb[0] * (1 - coeff),
						\ bg_rgb[1] * coeff + fg_rgb[1] * (1 - coeff),
						\ bg_rgb[2] * coeff + fg_rgb[2] * (1 - coeff)]
			let dim = '#'.join(map(dim_rgb, 'printf("%x", float2nr(v:val))'), '')
		endif
		execute printf('hi DarksideDim guifg=%s guisp=bg', dim)
	elseif &t_Co == 256
		if a:coeff < 0 && exists('g:darkside_conceal_ctermfg')
			let dim = g:darkside_conceal_ctermfg
		elseif fg <= -1 || bg <= -1
			throw s:unsupported()
		else
			let coeff = s:coeff(a:coeff)
			let fg = s:gray_contiguous(fg)
			let bg = s:gray_contiguous(bg)
			let dim = s:gray_ansi(float2nr(bg * coeff + fg * (1 - coeff)))
		endif
		if type(dim) == 1
			execute printf('hi DarksideDim ctermfg=%s', dim)
		else
			execute printf('hi DarksideDim ctermfg=%d', dim)
		endif
	else
		throw 'Unsupported terminal. Sorry.'
	endif
endfunction

function! s:getpos()
	let pos = exists('*getcurpos')? getcurpos() : getpos('.')
	let start = searchpos(s:darkside_bop, 'cbW')[0]
	call setpos('.', pos)
	let end = searchpos(s:darkside_eop, 'W')[0]
	call setpos('.', pos)
	return [start, end]
endfunction

function! s:empty(line)
	return (a:line =~# '^\s*$')
endfunction
function! s:clear_hl()
	while exists('w:darkside_match_ids') && !empty(w:darkside_match_ids)
		silent! call matchdelete(remove(w:darkside_match_ids, -1))
	endwhile
endfunction


function! s:lighten()
	if index(s:ignored_files,&ft)>=0
		call s:clear_hl()
		return
	endif
	if !exists('w:darkside_previous_selection')
		let w:darkside_previous_selection = [0, 0, 0, 0]
	endif

	let curr = [line('.'), line('$')]
	if curr ==# w:darkside_previous_selection[0 : 1]
		return
	endif

	let paragraph = s:getpos()
	if paragraph ==# w:darkside_previous_selection[2 : 3]
		return
	endif

	call s:clear_hl()
	call call('s:darken', paragraph)
	let w:darkside_previous_selection = extend(curr, paragraph)
endfunction

function! s:darken(startline,endline)
	let w:darkside_match_ids = get(w:, 'darkside_match_ids', [])
	let priority = get(g:, 'darkside_priority', 10)
	call add(w:darkside_match_ids, matchadd('DarksideDim', '\%<'.a:startline .'l', priority))
	if a:endline > 0
		call add(w:darkside_match_ids, matchadd('DarksideDim', '\%>'.a:endline .'l', priority))
	endif
endfunction

function! s:start()
	try
		call s:dim(s:darkside_coeff)
	catch
		return s:error(v:exception)
	endtry

	:augroup darkside
	:	autocmd!
	:	autocmd CursorMoved,CursorMovedI * call s:lighten()
	:	" autocmd ColorScheme * try
	:	" 			\|   call s:dim(s:darkside_coeff)
	:	" 			\| catch
	:	" 				\|   call s:stop()
	:	" 				\|   throw v:exception
	:	" 				\| endtry
	:augroup END
	" FIXME: We cannot safely remove this group once Darkside started
	:augroup darkside_win_event
	:	autocmd!
	:	autocmd WinEnter * call s:reset()
	:	autocmd WinLeave * call s:darken(line('$'),0)
	:augroup END
	doautocmd CursorMoved
endfunction

function! s:reset()
	call s:stop()
	call s:start()
endfunction

function! s:stop()
	call s:clear_hl()
	:augroup darkside
	:	autocmd!
	:augroup END
	augroup! darkside
	unlet! w:darkside_previous_selection w:darkside_match_ids
endfunction

function! darkside#execute(bang)
	if a:bang
		call s:stop()
	else
		call s:start()
	endif
endfunction

function! s:prompt(string)
	call inputsave()
	let name = input('Enter name: '.a:string)
	call inputrestore()
endfunction
let &cpo = s:cpo_save
unlet s:cpo_save
