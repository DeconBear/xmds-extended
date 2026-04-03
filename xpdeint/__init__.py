"""XMDS2 package initialisation."""

import sys


def _install_cgi_compat():
    """Provide the removed stdlib ``cgi`` module on Python 3.13+."""
    if 'cgi' in sys.modules:
        return

    try:
        import cgi  # noqa: F401
    except ModuleNotFoundError:
        from xpdeint import _cgi_compat

        sys.modules['cgi'] = _cgi_compat


_install_cgi_compat()
