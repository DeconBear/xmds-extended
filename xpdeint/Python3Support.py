#!/usr/bin/env python3
# encoding: utf-8
"""
Python3Support.py

Created by Noah Ingham on 2017-05-05.

Copyright (c) 2008-2012, Graham Dennis

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

This module adds missing features from python 2.4 that are
available in later versions which xpdeint depends on.
"""

from __future__ import print_function

# Set basestring to refer to str in Python 3
try:
  basestring
except NameError:
  import builtins
  builtins.basestring = str

