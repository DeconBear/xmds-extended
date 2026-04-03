"""Small subset of the removed stdlib :mod:`cgi` module.

This is only here so Cheetah3 can import on Python 3.13+, where ``cgi`` was
removed. XMDS itself does not rely on CGI form parsing, so we keep the surface
area intentionally small but compatible with ``FieldStorage.getvalue``.
"""

from __future__ import annotations

from dataclasses import dataclass
from html import escape
import os
from typing import Dict, Iterable, List, Optional
from urllib.parse import parse_qs, parse_qsl


def parse(fp=None, environ=None, keep_blank_values=False, strict_parsing=False):
    """Parse query data into a dict of lists."""
    environ = environ or os.environ
    method = environ.get('REQUEST_METHOD', 'GET').upper()

    if method == 'POST':
        content_length = environ.get('CONTENT_LENGTH', '0').strip() or '0'
        length = int(content_length)
        data = (fp.read(length) if fp is not None else '').decode() if isinstance(fp.read(0) if fp is not None else b'', bytes) else (fp.read(length) if fp is not None else '')
    else:
        data = environ.get('QUERY_STRING', '')

    return parse_qs(
        data,
        keep_blank_values=keep_blank_values,
        strict_parsing=strict_parsing,
    )


def parse_header(line):
    """Return a header value and any parameters."""
    if not line:
        return '', {}

    parts = [part.strip() for part in line.split(';')]
    key = parts[0]
    params = {}
    for part in parts[1:]:
        if '=' not in part:
            continue
        name, value = part.split('=', 1)
        params[name.strip().lower()] = value.strip().strip('"')
    return key, params


@dataclass
class MiniFieldStorage:
    name: str
    value: str


class FieldStorage(dict):
    """Tiny compatibility wrapper for the subset Cheetah touches."""

    def __init__(
        self,
        fp=None,
        headers=None,
        outerboundary=b'',
        environ: Optional[Dict[str, str]] = None,
        keep_blank_values=False,
        strict_parsing=False,
        limit=None,
        encoding='utf-8',
        errors='replace',
        max_num_fields=None,
        separator='&',
    ):
        del headers, outerboundary, limit, max_num_fields, separator

        environ = environ or os.environ
        data = self._read_form_data(
            fp=fp,
            environ=environ,
            encoding=encoding,
            errors=errors,
        )
        parsed = parse_qs(
            data,
            keep_blank_values=keep_blank_values,
            strict_parsing=strict_parsing,
            encoding=encoding,
            errors=errors,
        )

        super().__init__(
            {
                key: [MiniFieldStorage(key, value) for value in values]
                for key, values in parsed.items()
            }
        )

    @staticmethod
    def _read_form_data(fp, environ, encoding, errors):
        method = environ.get('REQUEST_METHOD', 'GET').upper()
        if method == 'POST':
            content_length = environ.get('CONTENT_LENGTH', '0').strip() or '0'
            try:
                length = int(content_length)
            except ValueError:
                length = 0
            if fp is None:
                return ''
            raw = fp.read(length)
        else:
            raw = environ.get('QUERY_STRING', '')

        if isinstance(raw, bytes):
            return raw.decode(encoding, errors)
        return raw

    def getvalue(self, key, default=None):
        values = self.getlist(key)
        if not values:
            return default
        if len(values) == 1:
            return values[0]
        return values

    def getlist(self, key) -> List[str]:
        items = self.get(key, [])
        return [item.value if isinstance(item, MiniFieldStorage) else item for item in items]

    def getfirst(self, key, default=None):
        values = self.getlist(key)
        return values[0] if values else default


__all__ = [
    'FieldStorage',
    'MiniFieldStorage',
    'escape',
    'parse',
    'parse_header',
    'parse_qs',
    'parse_qsl',
]
