#!/usr/bin/env python3
# encoding: utf-8
"""
run_tests.py

Created by Graham Dennis on 2008-06-15.

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

"""

import xpdeint.Python24Support

import os
import io
import re
import sys
import getopt
import shutil
import hashlib
import unittest
import subprocess

#from io import open
from xml.dom import minidom
import xpdeint.minidom_extras
from xpdeint import CodeParser

from xpdeint.XSILFile import XSILFile

import numpy

help_message = '''
The help message goes here.
'''


REPO_ROOT = os.path.abspath(os.path.dirname(__file__))
TEST_USER_DATA_ROOT = os.path.join(REPO_ROOT, '.xmds-test-home')


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


def _test_environment():
  env = os.environ.copy()
  pythonpath_entries = [REPO_ROOT]
  if env.get('PYTHONPATH'):
    pythonpath_entries.append(env['PYTHONPATH'])
  env['PYTHONPATH'] = os.pathsep.join(pythonpath_entries)
  if not os.path.isdir(TEST_USER_DATA_ROOT):
    os.makedirs(TEST_USER_DATA_ROOT)
  env['XMDS_USER_DATA'] = TEST_USER_DATA_ROOT
  if os.name != 'nt':
    return env

  prefixes = [
    os.path.join(REPO_ROOT, '.conda-xmds-libs'),
    os.environ.get('CONDA_PREFIX'),
    sys.prefix,
    os.path.dirname(sys.executable),
  ]
  runtime_paths = []
  for prefix in _iter_existing_paths(prefixes):
    runtime_paths.extend([
      os.path.join(prefix, 'Library', 'bin'),
      os.path.join(prefix, 'bin'),
    ])

  runtime_paths = list(_iter_existing_paths(runtime_paths))
  if runtime_paths:
    env['PATH'] = os.pathsep.join(runtime_paths + [env.get('PATH', '')])
  return env


def _xmds2_command(absPath):
  return [sys.executable, os.path.join(REPO_ROOT, 'bin', 'xmds2'), '--no-version', absPath]


def _simulation_command(simulationName):
  if os.name == 'nt':
    return '".\\\\%s.exe"' % simulationName
  return '"./%s"' % simulationName


def _as_text(output):
  if isinstance(output, bytes):
    return output.decode('utf-8', 'replace')
  return output


class Usage(Exception):
  def __init__(self, msg):
    self.msg = msg

def pass_nan_test(array1, array2):
    """Return `True` if isNaN(`array1`) == isNaN(`array2`)"""
    # NaN test. array2 is allowed to be NaN at an index if array1 is also NaN there.
    nanTestPassed = numpy.equal(numpy.isnan(array1), numpy.isnan(array2)).all()
    return nanTestPassed

def array_approx_equal(array1, array2, absTol, relTol):
  """Return `True` if all of (`array1` - `array2`) <= `absTol` or (`array1` - `array2`) <= `relTol` * `array2`"""
  absdiff = array1 - array2
  abssum = numpy.abs(array1 + array2)

  # NaN values would fail this test. So we have to exclude them. But only exclude them if array2 (the expected results)
  # have NaNs in the same places

  if numpy.isnan(array1.all()) == numpy.isnan(array2.all()):
    # There are NaNs in the answer, but they are in the same place for both expected and current current simulation results.
    # This means we can remove them.
    absdiff = absdiff[~numpy.isnan(array1)]
    abssum = abssum[~numpy.isnan(array2)]

  return numpy.logical_or(absdiff <= 0.5 * relTol * abssum, absdiff <= absTol).all()


def scriptTestingFunction(root, scriptName, testDir, absPath, self):
  if not os.path.exists(testDir):
    os.makedirs(testDir)

  proc = subprocess.Popen(_xmds2_command(absPath),
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,
                          cwd=testDir,
                          env=_test_environment())
  (stdout, stderr) = proc.communicate()
  stdout = _as_text(stdout)
  stderr = _as_text(stderr)
  returnCode = proc.wait()
  
  message = ''.join(["\n%(handleName)s:\n%(content)s" % locals() for handleName, content in [('stdout', stdout), ('stderr', stderr)] if content])
  
  # A few tests require specific features.  If it isn't available, skip the test
  # rather than failing.
  # The skip functionality for the unittest class is only available
  # in python 2.7 and later, so check for that too.
  if returnCode != 0 and sys.version_info[:2] >= (2, 7):
    # A few tests require XMDS1. If XMDS1 isn't present we should just
    # skip that test rather than failing.
    if re.search(r'^The missing \w+ feature\(s\) were: .*xmds.*', message, re.MULTILINE):
      self.skipTest("Skipping test as XMDS1 is required and not installed")
    if re.search(r'^The missing \w+ feature\(s\) were:', message, re.MULTILINE):
      self.skipTest("Skipping test as feature required is not installed")
    if re.search(r'xmds2 could not find MPI|MPI not found', message, re.MULTILINE):
      self.skipTest("Skipping test as MPI is required and not installed")
    if re.search(r'This script requires the python package', message, re.MULTILINE):
      self.skipTest("Skipping test as python package required is not installed")

  self.assertTrue(returnCode == 0, ("Failed to compile." % locals()) + message)
  
  xmlDocument = minidom.parse(absPath)
  simulationElement = xmlDocument.getChildElementByTagName('simulation')
  nameElement = simulationElement.getChildElementByTagName('name')
  testingElement = simulationElement.getChildElementByTagName('testing')
  
  simulationName = nameElement.innerText()
  
  # If the source is the same as the last known good, then we don't need to compile or execute the simulation.
  sourceFilePath = os.path.join(testDir, simulationName + '.cc')
  checksumFilePath = os.path.join(testDir, simulationName + '_last_known_good.checksum')

  #sourceContents = file(sourceFilePath).read()

  with io.open(sourceFilePath, 'r') as f:
    sourceContents = f.read()

  h = hashlib.sha1()
  h.update(sourceContents.encode('utf-8'))
  currentChecksum = h.hexdigest()
  
  if os.path.exists(checksumFilePath):
    #lastKnownGoodChecksum = file(checksumFilePath).read()

    with io.open(checksumFilePath, 'r') as f:
      lastKnownGoodChecksum = f.read()


    if lastKnownGoodChecksum == currentChecksum:
      # The checksums check out, so we don't need to go any further
      return
  
  # Now we have compiled, we need to copy any input data needed and then run the simulation
  inputXSILElements = testingElement.getChildElementsByTagName('input_xsil_file', optional=True)
  
  filesToCopy = []
  
  for inputXSILElement in inputXSILElements:
    name = inputXSILElement.getAttribute('name').strip()
    filesToCopy.append(name)
    inputXSILFile = XSILFile(os.path.join(os.path.split(absPath)[0], name), loadData=False)
    filesToCopy.extend([os.path.join(os.path.split(name)[0], xsil.data.filename) for xsil in inputXSILFile.xsilObjects if hasattr(xsil.data, 'filename')])
  
  for fileToCopy in filesToCopy:
    sourceFile = os.path.join(os.path.split(absPath)[0], fileToCopy)
    shutil.copy(sourceFile, testDir)
  
  # Allow command-line arguments to be specified for the simulation
  commandLineElement = testingElement.getChildElementByTagName('command_line', optional=True)
  argumentsElement = testingElement.getChildElementByTagName('arguments', optional=True)
  commandLineString = _simulation_command(simulationName)
  if commandLineElement:
    # The command line element overrides the prefix
    commandLineString = commandLineElement.innerText().strip()
    if os.name == 'nt':
      commandLineString = commandLineString.replace('./' + simulationName, '.\\\\' + simulationName + '.exe')
  if argumentsElement:
    commandLineString += ' ' + argumentsElement.innerText().strip()
  
  simulationProc = subprocess.Popen(commandLineString,
                                    shell=True,
                                    stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE,
                                    cwd=testDir,
                                    env=_test_environment())
  (stdout, stderr) = simulationProc.communicate()
  stdout = _as_text(stdout)
  stderr = _as_text(stderr)
  returnCode = simulationProc.wait()
  
  self.assertTrue(returnCode == 0, "Failed to execute compiled simulation correctly. Got returnCode %(returnCode)i;\nstdout = %(stdout)s;\nstderr = %(stderr)s\n" % locals())
  
  # The next thing to check is that the generated data agrees with the expected data to within the set error margins.
  xsilFileElements = testingElement.getChildElementsByTagName('xsil_file', optional=True)
  for xsilFileElement in xsilFileElements:
    sourceFile = xsilFileElement.getAttribute('name').strip()
    expectedResultsFile = xsilFileElement.getAttribute('expected').strip()
    # Defaults
    absoluteTolerance = 0 
    relativeTolerance = 1e-9
    
    if xsilFileElement.hasAttribute('absolute_tolerance'):
      absoluteTolerance = float(xsilFileElement.getAttribute('absolute_tolerance'))
    if xsilFileElement.hasAttribute('relative_tolerance'):
      relativeTolerance = float(xsilFileElement.getAttribute('relative_tolerance'))
    
    resultsFullPath = os.path.join(testDir, sourceFile)
    results = XSILFile(resultsFullPath)
    expectedResultsFullPath = os.path.join(os.path.split(absPath)[0], expectedResultsFile)
    if not os.path.exists(expectedResultsFullPath):
      sys.stderr.write("Expected results file '%(expectedResultsFile)s' missing. Using current. " % locals())
      # If there are any NaN's in the results, issue a warning.
      for mgNum, o in enumerate(results.xsilObjects):
        for v in o.independentVariables:
          if numpy.isnan(v['array']).any():
            sys.stderr.write("Warning: Coordinate '%s' in moment group %i of file '%s' contains a NaN." % (v['name'], mgNum+1, sourceFile))
        for v in o.dependentVariables:
          if numpy.isnan(v['array']).any():
            sys.stderr.write("Warning: Dependent variable '%s' in moment group %i of file '%s' contains a NaN." % (v['name'], mgNum+1, sourceFile))
      
      #resultsFileContents = file(resultsFullPath).read()
      with io.open(resultsFullPath, 'r') as f:
        resultsFileContents = f.read()

      
      for xsilObject in results.xsilObjects:
        if hasattr(xsilObject.data, 'filename'):
          # If the moment group has a data file name, then we need to copy it to the expected results file
          newDataFilename = xsilObject.data.filename.replace(os.path.splitext(sourceFile)[0], os.path.splitext(expectedResultsFile)[0], 1)
          
          resultsFileContents = resultsFileContents.replace(xsilObject.data.filename, newDataFilename)
          
          shutil.copyfile(os.path.join(testDir, xsilObject.data.filename),
                          os.path.join(os.path.split(absPath)[0], newDataFilename))
      
      #file(expectedResultsFullPath, 'w').write(resultsFileContents)
      with io.open(expectedResultsFullPath, 'w') as f:
        f.write(resultsFileContents)

    else:
      # We enter this path for each xsil file in a testing element, provided a previous
      # expected result exists that we can can compare with
      # results is the current run results
      expectedResults = XSILFile(expectedResultsFullPath)
      
      self.assertTrue(len(results.xsilObjects) == len(expectedResults.xsilObjects))
      
      momentGroupElements = xsilFileElement.getChildElementsByTagName('moment_group', optional=True)

      # If moment groups elements are specfically listed in the testing XML element, make sure the 
      # number listed corresponds to the number of xsilobjects in the results. 
      # If they're no listed in the testing block, set up a blank vector for the moment groups
      # with a number of entry equal to the number of xsilobjects
      if momentGroupElements:
        self.assertTrue(len(momentGroupElements) == len(results.xsilObjects))
      else:
        momentGroupElements = [None]*len(results.xsilObjects)
      
      # In the for loop below, the "enumerate" keyword assigns a loop counter to the variable mgNum
      # The "zip" keyword creates a tuple from the three listed objects, and sets up an iterator over
      # them that finishes when the shortest of the 3 lists of elements is exhausted
      for mgNum, (o1, o2, mgElem) in enumerate(zip(results.xsilObjects, expectedResults.xsilObjects, momentGroupElements)):
        # o1.name is something like "moment_group_3" or "breakpoint"
        # o1.independentVariables is a list of independent variables. Each element in the list is a dict.
        #    Each dict has keys like "name", "length", "array". "name" are things like "t", "x", "y" etc.
        # o1.dependentVariables is a list with the outputs of a single moment group, so things like real and imaginary
        #    parts of a potential vector. If there are four moments, the list will have four elements. Each element
        #    is a dictionary with keys "name" and "array". "name" is the moment name. "array" is an array with all
        #    the data for that moment. 

        currentAbsoluteTolerance = absoluteTolerance
        currentRelativeTolerance = relativeTolerance
        self.assertTrue(len(o1.independentVariables) == len(o2.independentVariables),
                     "The number of independent variables in moment group %(mgNum)i doesn't match." % locals())

        self.assertTrue(len(o1.dependentVariables) == len(o2.dependentVariables),
                     "The number of dependent variables in moment group %(mgNum)i doesn't match." % locals())
        
        if mgElem:
          if mgElem.hasAttribute('absolute_tolerance'):
            currentAbsoluteTolerance = float(mgElem.getAttribute('absolute_tolerance'))
          if mgElem.hasAttribute('relative_tolerance'):
            currentRelativeTolerance = float(mgElem.getAttribute('relative_tolerance'))
        
        self.assertTrue(currentAbsoluteTolerance != None and currentRelativeTolerance != None, "An absolute and a relative tolerance must be specified.")
        
        for v1, v2 in zip(o1.independentVariables, o2.independentVariables):
          self.assertTrue(v1['name'] == v2['name'])
          self.assertTrue(v1['length'] == v2['length'])
          # These are the coordinates, we just specify a constant absolute and relative tolerance.
          # No-one should need to change these
          self.assertTrue(array_approx_equal(v1['array'], v2['array'], 1e-7, 1e-6),
                      "Coordinate '%s' in moment group %i of file '%s' didn't pass tolerance criteria." % (v1['name'], mgNum+1, sourceFile))
        
        # Now we have to start being careful. The assert below used to work in Python 2:

        # for v1, v2 in zip(o1.dependentVariables, o2.dependentVariables):
        #  self.assertTrue(v1['name'] == v2['name'])

        # But in Python 3 the assert can sometimes fail, because dictionary hashing became random. This means iterating over a dict
        # can give varying element orders per iteration. This in turn means the "first" element of this test run may not
        # be the same as the "first" element of the saved run we're comparing against. 
        #
        # This should always be safe for independent variables (I think) because there's only one per moment group.
        # But there may be several dependent variables (moments) per moment group, and their dict order when iterated
        # over may be different to the expected value file's iterated dict order. 
        # 
        # So for Python 3 we need to change the code to match up moments by name within the moment group
        # when comparing, not just go by position order.
        #
        # To do this, given a list o1.dependentVariables, and a list o2.dependentVariables we need to reorder 
        # both lists so they have same order, based on the "name" key of each list element

        o1.dependentVariables.sort(key = lambda DepVar: DepVar['name']) 
        o2.dependentVariables.sort(key = lambda DepVar: DepVar['name'])

        for v1, v2 in zip(o1.dependentVariables, o2.dependentVariables):

          self.assertTrue(v1['name'] == v2['name'])
          self.assertTrue(pass_nan_test(v1['array'], v2['array']),
                       "Dependent variable '%s' in moment group %i of file '%s' had a NaN where the expected results didn't (or vice-versa)." % (v1['name'], mgNum+1, sourceFile))
          self.assertTrue(array_approx_equal(v1['array'], v2['array'], currentAbsoluteTolerance, currentRelativeTolerance),
                       "Dependent variable '%s' in moment group %i of file '%s' failed to pass tolerance criteria." % (v1['name'], mgNum+1, sourceFile))
  
  # Following gymnastics are to make the code work for both Python 2 and Python 3
  try:
    basestring # If this doesn't throw an error we're using Python 2
    with io.open(checksumFilePath, 'w') as f:
      f.write(currentChecksum.decode('utf-8'))
  except NameError:
    # Okay, we're using Python 3
    with io.open(checksumFilePath, 'w') as f:
      f.write(currentChecksum)


  
  lastKnownGoodSourcePath = os.path.join(testDir, simulationName + '_last_known_good.cc')
  #file(lastKnownGoodSourcePath, 'w').write(sourceContents)

  with io.open(lastKnownGoodSourcePath, 'w') as f:
    f.write(sourceContents)

def partial(func, *args, **keywords):
  def newfunc(*fargs, **fkeywords):
    newkeywords = keywords.copy()
    newkeywords.update(fkeywords)
    return func(*(args + fargs), **newkeywords)
  return newfunc


def main(argv=None):
  verbose = False
  
  if argv is None:
    argv = sys.argv
  try:
    try:
      opts, args = getopt.getopt(argv[1:], "ho:v", ["help", "output="])
    except getopt.error as msg:
      raise Usage(msg)
  
    # option processing
    for option, value in opts:
      if option == "-v":
        verbose = True
      if option in ("-h", "--help"):
        raise Usage(help_message)
      if option in ("-o", "--output"):
        output = value
  
  except Usage as err:
    sys.stderr.write(sys.argv[0].split("/")[-1] + ": " + str(err.msg))
    sys.stderr.write("\t for help use --help")
    return 2
  
  basePath = os.path.dirname(__file__)
  
  resultsPath = os.path.join(basePath, 'testsuite_results')
  if not os.path.exists(resultsPath):
    os.mkdir(resultsPath)
  resultsPath = os.path.abspath(resultsPath)
  
  print(("Saving test results in %(resultsPath)s" % locals()))
  
  testsuites = {}
  baseSuiteName = 'testsuite'
  baseSuitePath = os.path.join(basePath, baseSuiteName)
  
  for root, dirs, files in os.walk(baseSuitePath):
    # First remove directories we don't want to traverse
    for dirName in ['.svn']:
      if dirName in dirs:
        dirs.remove(dirName)
    # Remove the 'testsuite/' part of the path
    dirRelativeToBase = root[(len(baseSuitePath)+1):]
    if dirRelativeToBase:
      testSuiteName = os.path.join(baseSuiteName, dirRelativeToBase)
    else:
      testSuiteName = baseSuiteName
    
    # If we have .xmds files in this path, then create a TestCase subclass
    xmdsTestScripts = [filename for filename in files if os.path.splitext(filename)[1].lower() == '.xmds']
    
    if xmdsTestScripts:
      class ScriptTestCase(unittest.TestCase):
        # Create test functions for each test script using 'scriptTestingFunction'
        # These test function names are of the form 'test_ScriptName'

        for scriptName in xmdsTestScripts:
          prefix = os.path.splitext(scriptName)[0]
          absPath = os.path.abspath(os.path.join(root, scriptName))
          testDir = os.path.join(resultsPath, dirRelativeToBase)
          locals()['test_' + prefix] = partial(scriptTestingFunction, root, scriptName, testDir, absPath)
          locals()['test_' + prefix].__doc__ = os.path.join(dirRelativeToBase, scriptName)
      
      # Create a TestSuite from that class
      suite = unittest.defaultTestLoader.loadTestsFromTestCase(ScriptTestCase)
      testsuites[testSuiteName] = suite
    
    if not testSuiteName in testsuites:
      testsuites[testSuiteName] = unittest.TestSuite()
    
    if not any(filename == 'do_not_run_tests_by_default' for filename in files):
      # Add our TestSuite as a sub-suite of all parent suites
      suite = testsuites[testSuiteName]
      head = testSuiteName
      while True:
        head, tail = os.path.split(head)
        if not head or not tail:
          break
        testsuites[head].addTest(suite)
  
  
  suitesToRun = list()
  if len(args):
    for suiteName in args:
      fullSuiteName = os.path.join(baseSuiteName, suiteName)
      if fullSuiteName in testsuites:
        suitesToRun.append(testsuites[fullSuiteName])
      else:
        sys.stderr.write("Unable to find test '%(suiteName)s'" % locals())
  else:
    suitesToRun.append(testsuites[baseSuiteName])
  suitesToRun.append(unittest.defaultTestLoader.loadTestsFromModule(CodeParser))
  
  fullSuite = unittest.TestSuite(tests=suitesToRun)
  
  return not unittest.TextTestRunner(verbosity = 2 if verbose else 1).run(fullSuite).wasSuccessful()


if __name__ == "__main__":
  sys.exit(main())
