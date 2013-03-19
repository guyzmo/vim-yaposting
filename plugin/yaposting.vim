
if exists("g:yaposting")
    finish
else
    let g:yaposting = 1
endif

if !has('python')
    echoerr "Error: Yaposting plugin requires Vim to be compiled with +python"
    finish
endif

"""

let g:yaposting#takeout  = "<Leader>mt"
let g:yaposting#reformat = "<Leader>mr"
let g:yaposting#oequotef = "<Leader>mm"
let g:yaposting#cleanrep = "<Leader>mc"
let g:yaposting#cleanreu = "<Leader>m<UP>"
let g:yaposting#cleanred = "<Leader>m<DOWN>"
let g:yaposting#highligh = "<Leader>mh"
let g:yaposting#cuthere  = "<Leader>mn"

let g:yaposting#marginleft  = 0
let g:yaposting#marginright = 8
let g:yaposting#textwidth   = 80
let g:yaposting#alinea      = 4

let g:yaposting#QuoteExpr = '>'
let g:yaposting#TakeOutExpr = '[…]'

let g:yaposting#CutHereBeg = '--------8<----------------8<----------------8<---------------8<--------'
let g:yaposting#CutHereEnd = '-------->8---------------->8---------------->8--------------->8--------'

" Here be dragons

python <<EOS
import vim
import sys
import os.path
curpath = vim.eval("getcwd()")
libpath = os.path.join(os.path.dirname(os.path.dirname(vim.eval("expand('<sfile>:p')"))), 'pylibs')
sys.path = [os.path.dirname(libpath), libpath, curpath] + sys.path

import mail_format

def _oe_quotefix(beg, end, *arg):
    encoding = vim.eval("&encoding")
    m = mail_format.Mail("\n".join(vim.current.buffer[beg-1:end])).oe_quotefix(strip_signature=True, 
                                                                    reformat=True,
                                                                    linewidth=72)
    return m.__str__().encode(encoding).split("\n")

def _take_out(beg, end, *arg):
    encoding = vim.eval("&encoding")
    quote = vim.eval("g:yaposting#QuoteExpr")
    takeoutexpr = vim.eval("g:yaposting#TakeOutExpr")
    vim.command("let winview = winsaveview()")
    if beg == end:
        beg, end, quote = mail_format.Quote(quote=quote).find_current_level_boundaries(vim.current.buffer[:], curline=beg)
    else:
        qbeg, qend, quote = mail_format.Quote(quote=quote).find_current_level_boundaries(vim.current.buffer[beg-1:end])
        beg = qbeg+beg-1
        end = qbeg+end-1
    vim.command("norm "+str(beg)+"GV"+str(end)+"Gs"+quote+takeoutexpr)
    vim.command("call winrestview(winview)")

def _clean_quotes(beg, end, *arg):
    encoding = vim.eval("&encoding")
    quote = vim.eval("g:yaposting#QuoteExpr")
    vim.command("let winview = winsaveview()")
    if beg == end:
        beg, end = mail_format.Quote(quote=quote).find_boundaries(vim.current.buffer[:])
    else:
        qbeg, qend = mail_format.Quote(quote=quote).find_boundaries(vim.current.buffer[beg-1:end])
        beg = qbeg+beg-1
        end = qbeg+end-1
    q = mail_format.Quote(quote=quote).reformat_quotes("\n".join(vim.current.buffer[beg-1:end]), 72)
    vim.current.buffer[beg-1:end] = q.encode(encoding).split("\n")
    vim.command("call winrestview(winview)")

def _inc_quote_level(beg, end, *arg):
    encoding = vim.eval("&encoding")
    quote = vim.eval("g:yaposting#QuoteExpr")
    vim.command("let winview = winsaveview()")
    q = mail_format.Quote(quote=quote).increase_quote_level("\n".join(vim.current.buffer[beg-1:end]), whole=True)
    vim.current.buffer[beg-1:end] = q.encode(encoding).split("\n")
    vim.command("call winrestview(winview)")

def _dec_quote_level(beg, end, *arg):
    encoding = vim.eval("&encoding")
    quote = vim.eval("g:yaposting#QuoteExpr")
    vim.command("let winview = winsaveview()")
    q = mail_format.Quote(quote=quote).decrease_quote_level("\n".join(vim.current.buffer[beg-1:end]))
    vim.current.buffer[beg-1:end] = q.encode(encoding).split("\n")
    vim.command("call winrestview(winview)")

def _justify(beg, end, *arg):
    encoding = vim.eval("&encoding")
    quote = vim.eval("g:yaposting#QuoteExpr")
    vim.command("let winview = winsaveview()")
    if beg == end:
        vim.command("norm vip")
        try:
            beg = vim.current.buffer.mark('<')[0]
            end = vim.current.buffer.mark('>')[0]
        except:
            vim.command("norm u")
            vim.command("norm vip")
            beg = vim.current.buffer.mark('<')[0]
            end = vim.current.buffer.mark('>')[0]
    justified = mail_format.Text(vim.current.buffer.range(beg-1, end)).justify(72, indent_first=4).encode(encoding)
    vim.command("norm d")
    vim.current.buffer[beg-1:end] = justified.encode(encoding).split("\n")
    vim.command("call winrestview(winview)")
EOS
command! -range -nargs=* Justify :python _justify(<line1>, <line2>, <f-args>)
command! -range -nargs=* OEQuoteFix :python _oe_quotefix(<line1>, <line2>, <f-args>)
command! -range -nargs=* CleanQuotes :python _clean_quotes(<line1>, <line2>, <f-args>)
command! -range -nargs=* IncQuoteLevel :python _inc_quote_level(<line1>, <line2>, <f-args>)
command! -range -nargs=* DecQuoteLevel :python _dec_quote_level(<line1>, <line2>, <f-args>)
command! -range -nargs=* TakeOut :python _take_out(<line1>, <line2>, <f-args>)

" Function: HighLightenment() {{{
" Purpose:  Sets up the mail highlights features
"           
" Features: * double-margin exposition
"           * enforces the mail syntax
" Author:   Bernard PRATZ <bernard@pratz.net>
function! HighLightenment()
    if s:highlights == 0
        let s:highlights = 1
    elseif s:highlights == 1
        let s:highlights = 0
        setl syn=mail
        match none
        return 0
    endif
    "let s:hi_notquoted = '/^\([\[A-Za-z0-9\]*\[|%>\]\s^V|]\)\@!\%(\%(.\%<'.s:textwidth.'v\)*\)\@>.\%(\n\zs\|\zs.*\)/'
    let s:hi_first     = '/\%>'. ( s:textwidth - s:marginright + 1 ) .'v.\+/'
    let s:hi_second     = '/\%>'. ( s:textwidth + 1 ) .'v.\+/'
    setl syn=mail
    exe ':syn match Search '.s:hi_first
    exe ':syn match Error '.s:hi_second
endfunction " }}}
function! s:DoMappings() " {{{
    " It does just make the mappings
    exe "nnoremap ".g:yaposting#takeout."  :TakeOut()<CR>"
    exe "vnoremap ".g:yaposting#takeout."  :TakeOut()<CR>"
    exe "nnoremap ".g:yaposting#reformat." :Justify()<CR>"
    exe "vnoremap ".g:yaposting#reformat." :Justify()<CR>"
    exe "nnoremap ".g:yaposting#oequotef." :OEQuoteFix()<CR>"
    exe "vnoremap ".g:yaposting#oequotef." :OEQuoteFix()<CR>"
    exe 'nnoremap '.g:yaposting#cleanrep.' :CleanQuotes()<CR>'
    exe 'vnoremap '.g:yaposting#cleanrep.' :CleanQuotes()<CR>'
    exe 'nnoremap '.g:yaposting#cleanreu.' :IncQuoteLevel()<CR>'
    exe 'vnoremap '.g:yaposting#cleanreu.' :IncQuoteLevel()<CR>'
    exe 'nnoremap '.g:yaposting#cleanred.' :DecQuoteLevel()<CR>'
    exe 'vnoremap '.g:yaposting#cleanred.' :DecQuoteLevel()<CR>'
    exe 'nnoremap '.g:yaposting#highligh.' :call HighLightenment()<CR>'
    exe 'nnoremap '.g:yaposting#cuthere.'  O'.g:yaposting#CutHereBeg.'<CR>'.g:yaposting#CutHereEnd.'<ESC>^O'
    exe 'vnoremap '.g:yaposting#cuthere.'  dO'.g:yaposting#CutHereBeg.'<CR>'.g:yaposting#CutHereEnd.'<ESC>P'
endfunction " }}}

sil call s:DoMappings()





