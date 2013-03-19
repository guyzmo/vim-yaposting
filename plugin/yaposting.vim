
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

let s:takeout  = "<Leader>qt"
let s:reformat = "<Leader>qr"
let s:oequotef = "<Leader>qm"
let s:cleanrep = "<Leader>qc"
let s:cleanreu = "<Leader>q<UP>"
let s:cleanred = "<Leader>q<DOWN>"
let s:highligh = "<Leader>qh"
let s:cuthere  = "<Leader>qn"

let s:marginleft  = 0
let s:textwidth   = 80
let s:alinea      = 4

let g:QuoteRegexp = '>'
" This is the signature footer pattern.
let s:SignPattern = '-- '

let s:CutHereBeg = '--------8<----------------8<----------------8<---------------8<--------'
let s:CutHereEnd = '-------->8---------------->8---------------->8--------------->8--------'

" Here be dragons

python <<EOS
import sys
#reload(sys)
#sys.setdefaultencoding('utf8')
sys.path += "../pylibs"
import mail_format
#reload(mail_format)

def _oe_quotefix(beg, end, *arg):
    encoding = vim.eval("&encoding")$
    m = mail_format.Mail("\n".join(vim.current.buffer[beg-1:end])).oe_quotefix(strip_signature=True, 
                                                                    reformat=True,
                                                                    linewidth=72)
    return m.__str__().encode(encoding).split("\n")

def _clean_quotes(beg, end, *arg):
    encoding = vim.eval("&encoding")$
    q = mail_format.Quote().reformat_quotes("\n".join(vim.current.buffer[beg-1:end]), 72)
    vim.current.buffer[beg-1:end] = q.encode(encoding).split("\n")

def _inc_quote_level(beg, end, *arg):
    encoding = vim.eval("&encoding")$
    q = mail_format.Quote().increase_quote_level("\n".join(vim.current.buffer[beg-1:end]), whole=True)
    vim.current.buffer[beg-1:end] = q.encode(encoding).split("\n")

def _dec_quote_level(beg, end, *arg):
    encoding = vim.eval("&encoding")$
    q = mail_format.Quote().decrease_quote_level("\n".join(vim.current.buffer[beg-1:end]))
    vim.current.buffer[beg-1:end] = q.encode(encoding).split("\n")

def _justify(beg, end, *arg):
    encoding = vim.eval("&encoding")$
    if beg == end:
        vim.command("norm vip")
        beg = vim.current.buffer.mark('<')[0]
        end = vim.current.buffer.mark('>')[0]
    justified = mail_format.Text(vim.current.buffer.range(beg-1, end).decode(encoding)).justify(72, indent_first=4).encode(encoding)
    vim.command("norm d")
    vim.current.buffer[beg-1:end] = justified.encode(encoding).split("\n")
EOS
command! -range -nargs=* Justify :python _justify(<line1>, <line2>, <f-args>)
command! -range -nargs=* OEQuoteFix :python _oe_quotefix(<line1>, <line2>, <f-args>)
command! -range -nargs=* CleanQuotes :python _clean_quotes(<line1>, <line2>, <f-args>)
command! -range -nargs=* IncQuoteLevel :python _inc_quote_level(<line1>, <line2>, <f-args>)
command! -range -nargs=* DecQuoteLevel :python _dec_quote_level(<line1>, <line2>, <f-args>)

" Function: TakeOut() {{{
" Purpose:  Takes out a paragraph (quoted or not)
"           
" Features: * Ask a question and put the taking out reason in brakets
"           * finds out paragraphs in quoted context
"           * support up to 30 level of quotation
" TODO:     * change the QuoteLevel() algorithm, which is not
"             optimum...
"           * make the selection visible to the user when selecting
"             in a quote or selecting the first sentence of the paragraph
" Author:   Bernard PRATZ <bernard@pratz.net>
function! TakeOut()
    function! s:BegQuotedParagraph()
    " Function to find the beginning of a quoted parapraph
        let curpos = line('.')
        let i = line('.')
        while i > 2
            if s:QuoteLevel(i-1) != s:QuoteLevel(i) || getline(i - 1) =~ '^\('.g:QuoteRegexp.'\)*\s*$'
                sil call cursor(curpos,0)
                return i
            endif
            let i = i - 1
        endwhile
    endfunction
    function! s:EndQuotedParagraph()
    " Function to find the end of a quoted paragraph
        let curpos = line('.')
        let i = line('.')
        while i < line('$')
            if s:QuoteLevel(i+1) != s:QuoteLevel(i) || getline(i + 1) =~ '^\('.g:QuoteRegexp.'\)*\s*$'
                sil call cursor(curpos,0)
                return i
            endif
            let i = i + 1
        endwhile
    endfunction
    " Function to remove a paragraph
    if getline('.') =~ '^\('.g:QuoteRegexp.'\)*\s*$'
        return -1
    elseif s:QuoteLevel(line('.')) == 0
        exe 'norm vip'
    else
        exe 'norm '.s:BegQuotedParagraph().'GV'.s:EndQuotedParagraph().'G'
    endif
    redraw
    let snippedtext = s:Input("Reason","snip")
    exe 'norm dO['.snippedtext.']'
endfunction "}}}
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
    exe "nmap ".s:takeout."  :call TakeOut()<CR>"
    exe "nmap ".s:reformat." :Justify()<CR>"
    exe "nmap ".s:oequotef." :OEQuoteFix()<CR>"
    exe 'nmap '.s:cleanrep.' :CleanQuotes()<CR>'
    exe 'nmap '.s:cleanreu.' :IncQuoteLevel()<CR>'
    exe 'nmap '.s:cleanred.' :DecQuoteLevel()<CR>'
    exe 'nmap '.s:highligh.' :call HighLightenment()<CR>'
    exe 'nmap '.s:cuthere.'  O'.s:CutHereBeg.'<CR>'.s:CutHereEnd.'<ESC>^O'
    exe 'vmap '.s:cuthere.'  :s/\(\_.*\)/'.s:CutHereBeg.'\1'.s:CutHereEnd.'<CR>'
endfunction " }}}

sil call s:DoMappings()





