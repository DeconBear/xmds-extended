#!/usr/bin/env python3
# encoding: utf-8

import importlib
import os


def resource_filename(anchor, resource_name):
    """Return a filesystem path for a bundled resource.

    XMDS ships resources from an unpacked source tree, so we can resolve them
    relative to the importing module/package without depending on
    pkg_resources.
    """
    module = importlib.import_module(anchor)

    if getattr(module, "__path__", None):
        base_path = os.path.abspath(next(iter(module.__path__)))
    else:
        base_path = os.path.dirname(os.path.abspath(module.__file__))

    parts = [part for part in resource_name.replace("\\", "/").split("/") if part]
    return os.path.normpath(os.path.join(base_path, *parts))
