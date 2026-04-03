#!/usr/bin/env python3
# encoding: utf-8

from . import Arguments
from . import AutoVectorise
from . import Benchmark
from . import Bing
from . import CFlags
from . import ChunkedOutput
from . import Diagnostics
from . import ErrorCheck
from . import Globals
from . import HaltNonFinite
from . import MaxIterations
from . import OpenMP
from . import Output
from . import Stochastic
from . import Transforms
from . import Validation

from . import OutputFormat
from .BinaryFormat import BinaryFormat
from .AsciiFormat import AsciiFormat
from .HDF5Format import HDF5Format

formatMapping = [(f.name, f) for f in [BinaryFormat, AsciiFormat, HDF5Format]]
del BinaryFormat, AsciiFormat, HDF5Format

OutputFormat.OutputFormat.outputFormatClasses.update(formatMapping)

