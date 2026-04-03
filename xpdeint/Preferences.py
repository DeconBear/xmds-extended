#!/usr/bin/env python3
# encoding: utf-8
import os

versionString = '3.1.0 "My kingdom for a tentacle"'

if 'XMDS_USER_DATA' in os.environ:
    xpdeintUserDataPath = os.environ['XMDS_USER_DATA']
else:
    xpdeintUserDataPath = os.path.join(os.path.expanduser('~'), '.xmds')
