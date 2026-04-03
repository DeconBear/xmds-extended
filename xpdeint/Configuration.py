#!/usr/bin/env python3
# encoding: utf-8
"""
Configuration.py

Created by Graham Dennis on 2009-03-01.

Copyright (c) 2009-2012, Graham Dennis

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

"""
import os, sys, shutil

from xpdeint.Preferences import xpdeintUserDataPath
from xpdeint.Utilities import unique
from xpdeint._resource_compat import resource_filename

import pickle, tempfile, shutil, logging

config_arg_cache_filename = os.path.join(xpdeintUserDataPath, 'xpdeint_config_arg_cache')

wafdir = os.path.normpath(resource_filename(__name__, 'waf'))
sys.path.insert(0, wafdir)

# Old embedded waf versions can hang on modern Windows/Python combinations when
# using their preforked helper pool. Force the simpler subprocess path.
os.environ.setdefault('WAF_NO_PREFORK', '1')

from waflib import Context, Options, Configure, Utils, Logs, Errors

waf_initialised = False


def _iter_existing_paths(paths):
    seen = set()
    for path in paths:
        if not path:
            continue
        norm = os.path.normpath(path)
        if norm in seen or not os.path.isdir(norm):
            continue
        seen.add(norm)
        yield norm


def _augment_windows_search_paths(includePaths, libPaths):
    if os.name != 'nt':
        return includePaths, libPaths

    prefixes = []
    cwd = os.getcwd()
    package_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    prefixes.append(os.path.join(cwd, '.conda-xmds-libs'))
    prefixes.append(os.path.join(package_root, '.conda-xmds-libs'))

    for prefix in [os.environ.get('CONDA_PREFIX'), sys.prefix, os.path.dirname(sys.executable)]:
        if prefix:
            prefixes.append(prefix)

    extra_includes = []
    extra_libs = []
    for prefix in _iter_existing_paths(prefixes):
        extra_includes.extend([
            os.path.join(prefix, 'Library', 'include'),
            os.path.join(prefix, 'include'),
        ])
        extra_libs.extend([
            os.path.join(prefix, 'Library', 'lib'),
            os.path.join(prefix, 'lib'),
        ])

    includePaths = unique(list(includePaths) + list(_iter_existing_paths(extra_includes)))
    libPaths = unique(list(libPaths) + list(_iter_existing_paths(extra_libs)))
    return includePaths, libPaths


def _windows_runtime_bin_paths(libPaths):
    runtime_paths = []
    for libPath in libPaths:
        libPath = os.path.normpath(libPath)
        candidates = []
        if libPath.lower().endswith(os.path.normpath(r'Library\lib').lower()):
            prefix = os.path.dirname(os.path.dirname(libPath))
            candidates.append(os.path.join(prefix, 'Library', 'bin'))
        if libPath.lower().endswith(os.path.normpath(r'lib').lower()):
            prefix = os.path.dirname(libPath)
            candidates.append(os.path.join(prefix, 'bin'))
        runtime_paths.extend(candidates)
    return list(_iter_existing_paths(runtime_paths))


def _write_windows_launcher(target_name, runtime_paths):
    launcher_path = target_name + '.cmd'
    runtime_prefix = ';'.join(runtime_paths)
    lines = [
        '@echo off',
        'setlocal',
    ]
    if runtime_prefix:
        lines.append('set "PATH=%s;%%PATH%%"' % runtime_prefix)
    lines.append('"%%~dp0%s.exe" %%*' % os.path.basename(target_name))
    with open(launcher_path, 'w', newline='\r\n') as launcher_file:
        launcher_file.write('\n'.join(lines) + '\n')

def initialise_waf():
    if waf_initialised: return
    
    Logs.init_log()
    
    Context.waf_dir = wafdir
    Context.top_dir = Context.run_dir = xpdeintUserDataPath
    Context.out_dir = os.path.join(xpdeintUserDataPath, 'waf_configure')
    Context.launch_dir = Context.top_dir
    
    wscript_path = resource_filename(__name__, 'support/wscript')
    Context.g_module = Context.load_module(wscript_path)
    Context.g_module.root_path = wscript_path
    Context.g_module.out = Context.out_dir
    Context.g_module.configure = configure_wrapper(Context.g_module.configure)
    Context.Context.recurse = \
        lambda x, y: getattr(Context.g_module, x.cmd or x.fun, Utils.nada)(x)
    
    Options.OptionsContext().execute()

    # The following line is to get around the warning
    #
    # CWD / is not under /home/mattias/xmds-2.2.3/examples, forcing --targets=* (run distclean?)
    #
    # which occurs whenever an xmds script is compiled. It's appearance seems to related to either
    # moving to Cheetah 3 from Cheetah 2, or more like updating the waf install from 1.6 to 2.0.
    # The warning comes from the BuildContext class in xpdeint/waf/waflib/Build.py, and is because
    # no build target has been set, so it assumes "*". 
    #
    # If the line below is placed before the Options.OptionsContext().execute() above it doesn't
    # work because the build target gets cleared. I can't find where waf is doing this, and I can't
    # figure out how to pass build targets in a way that works, so use the line of code below as
    # a workaround. It's probably a harmless workaround since it just mirrors what happens in the
    # end eventually.
    #
    # We still get the warning once when configuring or compiling the cheetah templates, but that
    # basically only happens once, so I don't care. That does show, however, that another build
    # process is called from somewhere else. - MTJ

    Options.options.targets = '*' 


def configure_wrapper(f):
    def _(ctx, *args, **kw):
        ctx.in_msg -= 1
        return f(ctx, *args, **kw)
    
    return _

def run_config(includePaths = None, libPaths = None):
    includePaths = includePaths or []
    libPaths = libPaths or []
    includePaths, libPaths = _augment_windows_search_paths(includePaths, libPaths)
    
    wafEnvironment = {}
    
    wafEnvironment['INCLUDES'] = unique(includePaths)
    wafEnvironment['LIBPATH'] = unique(libPaths)
    
    pickle.dump(wafEnvironment, open(config_arg_cache_filename, 'wb'))
    
    initialise_waf()
    
    ctx = Context.create_context('configure')
    ctx.options = Options.options
    ctx.jobs = 1
    Options.options.jobs = 1
    
    env = ctx.env
    
    env.append_unique('INCLUDES', includePaths)
    env.append_unique('LIBPATH', libPaths)
    env.append_unique('RPATH', libPaths)
    
    for key in ['CXX', 'CXXFLAGS', 'LINKFLAGS']:
        if key in os.environ:
            env[key] = os.environ[key]
    
    ctx.in_msg = 1
    
    ret = -1
    try:
        ret = ctx.execute()
    except Errors.ConfigurationError as e:
        print("Configuration failed.  Address the above issue to use xmds2.")
    
    print(("Config log saved to ", os.path.join(xpdeintUserDataPath, 'waf_configure', 'config.log')))

    
    # Copy wscript file to indicate what we configured with
    wscript_path = resource_filename(__name__, 'support/wscript')
    wscript_userdata_path = os.path.join(xpdeintUserDataPath, 'wscript')
    
    shutil.copyfile(wscript_path, wscript_userdata_path)
    return ret


def run_reconfig(includePaths = None, libPaths = None):
    includePaths = includePaths or []
    libPaths = libPaths or []
    
    wafEnvironment = {}
    
    if os.path.isfile(config_arg_cache_filename):
        wafEnvironment.update(pickle.load(open(config_arg_cache_filename, "rb")))
    includePaths.extend(wafEnvironment.get('INCLUDES', []))
    libPaths.extend(wafEnvironment.get('LIBPATH', []))
    includePaths, libPaths = _augment_windows_search_paths(includePaths, libPaths)
    
    return run_config(includePaths = includePaths, libPaths = libPaths)

def run_build(source_name, target_name, variant = 'default', buildKWs = {}, verbose = False, userCFlags = None):
    initialise_waf()
    
    source_name = str(source_name)
    target_name = str(target_name)
    
    cwd = os.getcwd()
    Context.launch_dir = cwd
    
    ctx = Context.create_context('build', top_dir = cwd, run_dir = cwd)
    ctx.load_envs()
    ctx.jobs = 1
    Options.options.jobs = 1
    
    available_variants = list(ctx.all_envs.keys())
    
    if not variant in available_variants:
        if variant == 'mpi':
            print("xmds2 could not find MPI. Do you have an MPI library (like OpenMPI) installed?")
            print("If you do, run 'xmds2 --reconfigure' to find it.")
        else:
            print(("xmds2 could not find build variant '%s'." % variant))
        return -1
    
    ctx.env = ctx.all_envs[variant]
    available_uselib = ctx.env.uselib
    
    uselib = buildKWs['uselib']
    # Expand the dependencies of any uselib variables
    Context.g_module.expand_dependencies_of_list(uselib, uselib[:], ctx.env)
    
    missing_uselib = set([uselib for uselib in buildKWs['uselib'] if uselib]).difference(available_uselib)
    if missing_uselib:
        print("This script requires libraries or features that xmds2 could not find.")
        print("Make sure these requirements are installed and then run 'xmds2 --reconfigure'.")
        print(("The missing %i feature(s) were: %s." % (len(missing_uselib), ', '.join(missing_uselib))))
        return -1
    
    buildKWs['uselib'].append('system')
    
    ctx.out_dir = cwd
    def build(ctx):
        ctx.program(
            source = [source_name],
            target = target_name,
            **buildKWs
        )
    Context.g_module.build = build
    
    if not verbose:
        ctx.to_log = lambda x: None
        Logs.log.setLevel(logging.WARNING)
    else:
        Logs.log.setLevel(logging.DEBUG)
        
        old_exec_command = ctx.exec_command
        def new_exec_command(cmd, **kw):
            if not isinstance(cmd, basestring):
                cmd_str = ' '.join([_ if ' ' not in _ else '"'+_+'"' for _ in cmd])
            else:
                cmd_str = cmd
            print(cmd_str)
            
            return old_exec_command(cmd, **kw)
        ctx.exec_command = new_exec_command
    
    ctx.store = lambda: None
    
    if userCFlags:
        def wrap(ctx):
            old_exec_command = ctx.exec_command
            def new_exec_command(cmd, **kw):
                assert isinstance(cmd, basestring)
                cmd = cmd + " " + userCFlags
                return old_exec_command(cmd, **kw)
            ctx.exec_command = new_exec_command
        wrap(ctx)
    
    
    try:
        ctx.execute()
        
        # Now clean up the intermediate file/s if we aren't in verbose mode
        if not verbose:
            tgen = ctx.get_tgen_by_name(target_name)
            for t in tgen.compiled_tasks:
                for n in t.outputs:
                    n.delete()
    except Errors.BuildError as err:
        if verbose:
            last_cmd = err.tasks[0].last_cmd
            if type(last_cmd) is list:
                last_cmd = ' '.join(last_cmd)
            if userCFlags:
                last_cmd = last_cmd + ' ' + userCFlags
                
            print("Failed command:")
            print(last_cmd)
        return -1

    if os.name == 'nt':
        runtime_paths = _windows_runtime_bin_paths(ctx.env.LIBPATH)
        _write_windows_launcher(target_name, runtime_paths)
    
    return 0
