#/usr/bin/env python
# -+- encoding: utf-8 -+-

__author__ = "Bernard Pratz <bernard at pratz dot net>"
__license__ = "GPLv3"

import re
import sys
reload(sys)
sys.setdefaultencoding('utf8')
import argparse

import textwrap
from itertools import groupby


class Mail():
    def __init__(self, mail):
        self.mail = mail
        self.quote = Quote()
        # matches on "------ Your message ------" from outlook
        self.oe_quote = re.compile(u"---*[\w ]+---*.*$", re.MULTILINE)
        # matches on header-type "key: value"
        self.header = re.compile(u"^(?P<key>[ \w-]+): *(?P<value>[\w:. ><@,+-]+)$", re.MULTILINE | re.UNICODE)
        # matches signature
        self.sign = re.compile(r"^--", re.MULTILINE)
        self.headers = []

    def take_away_headers(self):
        idx = 0
        self.headers = self.header.findall(self.mail)
        for m in self.header.finditer(self.mail):
            self.headers.append(m.groups())
        else:
            idx = m.end()
        self.mail = self.mail[idx:]

    def give_back_headers(self):
        out = u""
        for header in self.headers:
            out += u"%s: %s" % header
        else:
            self.headers = []
            self.mail = out + self.mail

    def remove_signature(self, quote=None):
        if not quote:
            quote = self.mail
        m = self.sign.search(quote)
        if m:
            quote = quote[0:m.span()[0]]
        if not quote:
            self.mail = quote
        else:
            return quote

    def oe_quotefix(self, strip_signature=False, reformat=False, linewidth=85, **kwargs):
        from_h = re.compile(r"(de|from|von)", re.UNICODE | re.IGNORECASE)
        date_h = re.compile(r"date", re.UNICODE | re.IGNORECASE)

        m = self.oe_quote.search(self.mail)
        if not m:
            beg_idx, end_idx = m.span()
        headers = dict()

        # strip quotes from reply, and record if there is a quote level
        quoted = self.quote.decrease_quote_level(self.mail[end_idx:])
        has_quote = (quoted == self.mail[end_idx:])

        if strip_signature:
            quoted = self.remove_signature(quoted)

        # find the index of the end of the quote introduction
        for m in self.header.finditer(quoted):
            headers.update(dict((m.groups(),)))
        else:
            last = m.end()

        # extract the "from" and "date" headers from the quote headers
        f, d = (None, None)
        for key, val in headers.iteritems():
            if from_h.search(key):
                f = val.encode('utf8')
            if date_h.search(key):
                d = val.encode('utf8')
            if f and d:
                break
        if d:
            if f:
                out = u"On %s, %s wrote:\n" % (d, f)
            else:
                out = u"On %s, you wrote:\n" % d
        else:
            if f:
                out = u" * %s wrote:\n" % f
            else:
                out = u" * You wrote:\n"

        if reformat:
            if has_quote:
                out += Text(quoted[last:]).justify(linewidth, **kwargs).decode('utf8')
            else:
                kwargs["prefix"] = "> "
                out += Text(quoted[last:]).justify(linewidth, **kwargs).decode('utf8')
        else:
            out += self.quote.increase_quote_level(quoted[last:], whole=True)

        out += self.mail[:beg_idx]
        self.mail = out

    def __repr__(self):
        return u"<Mail(%s)>" % repr(self.mail[:20])

    def __str__(self):
        return self.mail.encode('utf8')


class Quote():
    def __init__(self, quote=u">", quotes=[u">", u"|", u":"], citation=r"^On .* wrote:"):
        self.quotes = quotes
        self.quote = quote

        self.citation = re.compile(citation, re.MULTILINE)

        # matches on "> text"
        quote_re = r"^(%(q)s)([ %(q)s]*) ?(.*)"
        self.quote_re = re.compile(quote_re % {"q": u"|".join(quote)},
                                   re.MULTILINE)

    def find_begin_of_quote(self, paragraph):
        m = self.citation.search(paragraph)
        if m:
            return m.span()

    def find_boundaries(self, paragraph):
        if isinstance(paragraph, str):
            paragraph = paragraph.splitlines()
        i=1
        quote=[]
        for line in paragraph:
            if self.quote_re.match(line):
                quote.append(i)
            i += 1
        return (quote[0], quote[-1])

    def find_current_level_boundaries(self, paragraph, curline=1):
        level = {}
        curlevel = 0
        if isinstance(paragraph, str):
            paragraph = paragraph.splitlines()
        i=0
        for line in paragraph:
            m = self.quote_re.match(line)
            if m:
                n = m.group(1).count(">") + m.group(2).count(">")
            else:
                n = 0
            i += 1
            level.setdefault(n, []).append(i)
            if i == curline:
                curlevel = n

        quote = "%s%s" % (self.quote,
                          " "+(self.quote * (curlevel - 2))+" " if curlevel != 1 else "")

        return (level[curlevel][0], level[curlevel][-1], quote)

    def has_reply_quote(self, paragraph):
        if self.quote_re.search(paragraph):
            return True
        return False

    def cleanup_quotes(self, paragraph):
        if self.has_reply_quote(paragraph):
            return re.compile(r"^> >", re.MULTILINE).sub(">>", paragraph)

    def increase_quote_level(self, paragraph, whole=False):
        if whole or self.has_reply_quote(paragraph):
            return re.compile(r"^", re.MULTILINE).sub("%s " % self.quote, paragraph)
        return self.quote_re.sub(lambda m: '%s %s' % (self.quote, m.group(0)),
                                 paragraph)

    def decrease_quote_level(self, paragraph):
        if self.has_reply_quote(paragraph):
            def _requote(m):
                # in case there is no more quoting
                if len(m.group(2)) == 0:
                    # print only the text
                    return u"%s" % (m.group(3).strip())
                return u"%s %s" % (m.group(2).lstrip(), m.group(3))
            return self.quote_re.sub(_requote, paragraph)
        return paragraph

    def reformat_quotes(self, paragraph, linewidth=85, **kwargs):
        level = {}
        for line in paragraph.splitlines():
            m = self.quote_re.match(line)
            if m:
                n = m.group(1).count(">") + m.group(2).count(">")
            else:
                n = 0
            level.setdefault(n, []).append(line)

        out = str()
        for i in sorted(level.keys(), reverse=True):
            lines = [self.quote_re.sub(lambda m: m.group(3), line)
                     for line in level[i]]
            lines = u" ".join(lines)

            prefix = kwargs.get("prefix", "")
            quotes = " "+(self.quote * (i - 1))+" " if i != 1 else " "
            prefix = u"%s%s%s" % (prefix, self.quote, quotes)

            paragraph = Text(lines).justify(linewidth, prefix=prefix, **kwargs)

            out += paragraph
            out += "\n"
        return out


class Text():
    def __init__(self, text, force_utf8=False):
        if force_utf8:
            reload(sys)
            sys.setdefaultencoding('utf8')
        if isinstance(text, basestring):
            self.text = text.splitlines()
        else:
            self.text = text

    def justify(self, line_width, indent_first=0, indent=0, prefix=None,
                indent_only_first=False):
        out = []
        separator = u"\n\n"
        if prefix:
            separator = u"\n%s\n" % prefix
        for group_separator, line_iteration in groupby(self.text, key=lambda x: x.isspace()):
            if not group_separator:
                paragraph = ''.join(line_iteration)
                if len(paragraph) == 0:
                    continue
                out.append(Paragraph(paragraph).justify(line_width, indent_first,
                                                        indent, prefix))
                if indent_only_first:
                    indent_first = 0
        return separator.join(out)


class Paragraph():
    def __init__(self, text):
        self.text = text.decode('utf-8')

    def justify(self, line_width, indent_first=0, indent=0, prefix=None):
        if prefix and indent < len(prefix):
            indent = len(prefix)

        ptext = ('@' * indent_first) + self.text.lstrip()
        line_width = line_width - indent

        wrapped = textwrap.wrap(ptext, line_width)

        if len(wrapped) == 0:
            raise Exception("Error on wrapping")

        if len(wrapped) == 1:
            if indent:
                line = list(u" " * indent + self.text)
                if prefix:
                    line[0:len(prefix)] = list(prefix)
                self.text = u"".join(line)
            return self.text

        out = []

        for l in wrapped[:-1]:
            # count number of spaces to add
            # cut the string in words, and strip spaces
            words = filter(lambda x: not x == '', l.split(' '))
            ll = []
            for w in reversed(words):
                ll.append(['', w.decode('utf-8')])
            i = 0
            while len(u"".join([u"".join(w).decode('utf-8') for w in ll]).decode('utf-8')) < line_width:
                if i == len(ll) - 2:
                    i = 0
                else:
                    i += 1
                ll[i][0] += ' '

            ll = [u"".join(w) for w in ll]

            words = list((' ' * indent) + ''.join([w for w in reversed(ll)]))

            if indent_first and wrapped.index(l) == 0:
                words[0 + indent:indent_first + indent] = ' ' * indent_first
            if prefix:
                words[0:len(prefix)] = list(prefix)

            out.append(u"".join(words))
        if indent:
            line = list(u" " * indent + wrapped[-1])
            if prefix:
                line[0:len(prefix)] = list(prefix)
            out.append(u"".join(line))
        else:
            out.append(wrapped[-1])

        out = u"\n".join(out)

        return out


def start():
    """helper method to create a commandline utility"""
    parser = argparse.ArgumentParser(prog=sys.argv[0],
                                     description="Tool that justifies text")

    parser.add_argument("-a",
                        "--alinea",
                        default=0,
                        type=int,
                        dest="pindent",
                        action="store",
                        help='Indents the first line of the paragraph by the given value.')

    parser.add_argument("-1",
                        "--indent-only-first",
                        dest="indent_only_first",
                        action="store_true",
                        help='Indent only first paragraph.')

    parser.add_argument('-i',
                        '--indent',
                        default=0,
                        type=int,
                        dest='indent',
                        action='store',
                        help='Indents the whole paragraph by the given value.')

    parser.add_argument('-p',
                        '--prefix',
                        dest='prefix',
                        default=None,
                        help='Prefix all the text with the given string.')

    parser.add_argument('-j',
                        '--join-paragraphs',
                        dest='join',
                        action="store_true",
                        help='Treat the given text as one paragraph.')

    parser.add_argument('-f', '--file',
                        dest='infile', type=argparse.FileType('r'),
                        default=sys.stdin, help='File to indent')

    parser.add_argument(dest='line_width', nargs='?', default=85, type=int,
                        help='Width of the line.')

    args = parser.parse_args(sys.argv[1:])

    if args.join:
        print Paragraph(args.infile.read()).justify(args.line_width, indent=args.indent, indent_first=args.pindent, prefix=args.prefix)
    else:
        print Text(args.infile.readlines()).justify(args.line_width, indent=args.indent, indent_first=args.pindent, prefix=args.prefix).encode('utf-8')


if __name__ == "__main__":
    start()
