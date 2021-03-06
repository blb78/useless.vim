if exists('g:loaded_useless')
	finish
endif

let g:loaded_useless = 1
let s:invalid_opacity = 'Invalid opacity. Expected: 0.0 ~ 1.0'

let s:default_opacity = get(g:,'useless_opacity', 0.3)
let s:default_foreground = get(g:,'useless_foreground', synIDattr(synIDtrans(hlID('Normal')), 'fg#'))
let s:default_boundary_start = get(g:,'useful_boundary_start','')
let s:default_boundary_end = get(g:,'useful_boundary_end','')
let s:default_stay_useful = 0

let s:groups = get(g:,'useful_groups',{})
let s:filetypes = get(g:,'useful_filetypes',{})

let s:cpo_save = &cpo
set cpo&vim


function! s:onLeaving()
	if s:stay_useful
		return
	endif
	call s:uselessAround(line('$')+1,0,0,0)
endfunction

function! s:usefulBlock()
	let pos = exists('*getcurpos')? getcurpos() : getpos('.')
	let start =  searchpos(s:pattern_start, 'cbW')
	call setpos('.', pos)
	let end = searchpos(s:pattern_end, 'W')
	call setpos('.', pos)
	return [start[0], start[1],end[0],end[1]]
endfunction

function! s:uselessAround(start_lnum,start_col,end_lnum,end_col)
	let w:useless_match_ids = get(w:, 'useless_match_ids', [])
	let priority = get(g:, 'useless_priority', 10)
	call add(w:useless_match_ids, matchadd('UselessDim', '\%<'.a:start_lnum .'l', priority))
	call add(w:useless_match_ids, matchadd('UselessDim', '\%'.a:start_lnum .'l\%<'.a:start_col.'c', priority))
	if a:end_lnum > 0
		call add(w:useless_match_ids, matchadd('UselessDim', '\%>'.a:end_lnum.'l', priority))
		call add(w:useless_match_ids, matchadd('UselessDim', '\%'.a:end_lnum.'l\%>'.a:end_col.'c', priority))
	endif
endfunction

function! s:boundaryFree()
	return empty(s:pattern_start) && empty(s:pattern_end) ? 1 : 0
endfunction

function! s:highlighting()
	if s:boundaryFree()
		return
	endif

	let useful = s:usefulBlock()
	if useful ==# w:selection
		return
	endif

	call s:clearHL()
	call call('s:uselessAround', useful)
	let w:selection = useful
endfunction

function! s:hex2RGB(str)
	let str = substitute(a:str, '^#', '', '')
	return {'r':eval('0x'.str[0:1]), 'g':eval('0x'.str[2:3]),'b': eval('0x'.str[4:5])}
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

function! s:validate(opacity)
	let opacity = a:opacity < 0 ? s:default_opacity : a:opacity
	if opacity < 0 || opacity > 1
		return 0
	endif
	return 1
endfunction

function! s:error(msg)
	echohl ErrorMsg
	echo a:msg
	echohl None
endfunction

function! s:createGroup(opacity)
	let s:background = synIDattr(synIDtrans(hlID('Normal')), 'bg#')
	if has('gui_running') || has('termguicolors') && &termguicolors || has('nvim') && $NVIM_TUI_ENABLE_TRUE_COLOR
		if a:opacity < 0 && exists('g:useless_conceal_guifg')
			let dim = g:useless_conceal_guifg
		elseif empty(s:foreground) || empty(s:background)
			throw s:unsupported()
		else
			if !s:validate(a:opacity)| throw 'Invalid g:useless_opacity. Expected: 0.0 ~ 1.0' | endif
			let fg_rgb = s:hex2RGB(s:foreground)
			let bg_rgb = s:hex2RGB(s:background)
			let dim_rgb = [
						\(1.0 - a:opacity) * bg_rgb.r + a:opacity * fg_rgb.r ,
						\(1.0 - a:opacity) * bg_rgb.g + a:opacity * fg_rgb.g ,
						\(1.0 - a:opacity) * bg_rgb.b + a:opacity * fg_rgb.b ]
			let dim = '#'.join(map(dim_rgb, 'printf("%x", float2nr(v:val))'), '')
		endif
		execute printf('hi UselessDim guifg=%s guisp=bg', dim)
	elseif &t_Co == 256
		if a:opacity < 0 && exists('g:useless_conceal_ctermfg')
			let dim = g:useless_conceal_ctermfg
		elseif s:foreground <= -1 || s:background <= -1
			throw s:unsupported()
		else
			if !s:validate(a:opacity)| throw 'Invalid g:useless_opacity. Expected: 0.0 ~ 1.0' | endif
			let fg = s:gray_contiguous(s:foreground)
			let bg = s:gray_contiguous(s:background)
			let dim = s:gray_ansi(float2nr(fg * a:opacity + bg * (1 - a:opacity)))
		endif
		if type(dim) == 1
			execute printf('hi UselessDim ctermfg=%s', dim)
		else
			execute printf('hi UselessDim ctermfg=%d', dim)
		endif
	else
		throw 'Unsupported terminal. Sorry.'
	endif
endfunction

function! s:createHighlight()
	try
		call s:createGroup(s:default_opacity)
	catch
		call s:stop()
		return s:error(v:exception)
	endtry
endfunction

function! s:applySettings()
	let s:stay_useful = s:default_stay_useful
	let s:foreground = s:default_foreground
	let s:pattern_start = s:default_boundary_start
	let s:pattern_end = s:default_boundary_end
	let w:selection = [0, 0, 0, 0]
	for key in keys(s:groups)
		if index(s:groups[key]['filetypes'],&ft)>=0
			let s:pattern_start =  has_key(s:groups[key],'boundary_start') ? s:groups[key]['boundary_start'] : s:default_boundary_start
			let s:pattern_end =  has_key(s:groups[key],'boundary_end') ? s:groups[key]['boundary_end'] : s:default_boundary_end
			let s:foreground = has_key(s:groups[key],'useless_foreground') ? s:groups[key]['useless_foreground'] : s:default_foreground
			let s:stay_useful =  has_key(s:groups[key],'stay_useful') ? s:groups[key]['stay_useful'] : s:default_stay_useful
		endif
	endfor
	if has_key(s:filetypes,&ft)
		let s:pattern_start =  has_key(s:filetypes[&ft],'boundary_start') ? s:filetypes[&ft]['boundary_start'] : s:default_boundary_start
		let s:pattern_end =  has_key(s:filetypes[&ft],'boundary_end') ? s:filetypes[&ft]['boundary_end'] : s:default_boundary_end
		let s:foreground = has_key(s:filetypes[&ft],'useless_foreground') ? s:filetypes[&ft]['useless_foreground'] : s:default_foreground
		let s:stay_useful = has_key(s:filetypes[&ft],'stay_useful') ? s:filetypes[&ft]['stay_useful'] : s:default_stay_useful
	endif
endfunction

function! s:clearHL()
	while exists('w:useless_match_ids') && !empty(w:useless_match_ids)
		silent! call matchdelete(remove(w:useless_match_ids, -1))
	endwhile
endfunction

function! s:reset()
	call s:stop()
	call s:start()
endfunction

function! s:stop()
	call s:clearHL()
	:augroup useless
	:	autocmd!
	:augroup END
	augroup! useless
	":augroup useless_win_event
	":	autocmd!
	":augroup END
	"augroup! useless_win_event
	unlet! w:selection w:useless_match_ids
endfunction

function! s:start()
	call s:clearHL()
	call s:applySettings()
	call s:createHighlight()
	:augroup useless
	:	autocmd!
	:	autocmd CursorMoved,CursorMovedI * call s:highlighting()
	:	autocmd ColorScheme * call s:createHighlight()
	:augroup END
	:augroup useless_win_event
	:	autocmd!
	:	" FIXME: TermEnter is trigger when running fzf, but BufEnter too
	:	if has('nvim')
	:		autocmd WinEnter * call s:reset()
	:		autocmd WinLeave * call s:onLeaving()
	:		autocmd TermEnter * call s:stop()
	:		autocmd TermLeave * call s:start()
	:	else
	:		autocmd WinEnter,BufEnter * call s:reset()
	:		autocmd WinLeave,BufLeave * call s:onLeaving()
	:	endif
	:augroup END
	doautocmd CursorMoved
endfunction

function! useless#execute(bang)
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
