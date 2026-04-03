#!/usr/bin/env python3
# encoding: utf-8

from . import TransformMultiplexer
transformClasses = TransformMultiplexer.TransformMultiplexer.transformClasses

from . import _NoTransform
from . import NoTransformMPI
_NoTransform._NoTransform.mpiCapableSubclass = NoTransformMPI.NoTransformMPI
transformClasses['none'] = _NoTransform._NoTransform

from . import FourierTransformFFTW3
from . import FourierTransformFFTW3Threads
from . import FourierTransformFFTW3MPI
FourierTransformFFTW3.FourierTransformFFTW3.mpiCapableSubclass = FourierTransformFFTW3MPI.FourierTransformFFTW3MPI
transformClasses.update([(name, FourierTransformFFTW3.FourierTransformFFTW3) for name in ['dft', 'dct', 'dst', 'mpi']])

from . import BesselTransform
transformClasses.update([(name, BesselTransform.BesselTransform) for name in ['bessel', 'spherical-bessel']])
from . import BesselNeumannTransform
transformClasses['bessel-neumann'] = BesselNeumannTransform.BesselNeumannTransform

from . import HermiteGaussTransform
transformClasses['hermite-gauss'] = HermiteGaussTransform.HermiteGaussTransform

del transformClasses
