#!/usr/bin/env bash
set -e

# School channel: modest is the ONLY package shipping dmftproj (dft_tools was
# dropped from the school set), so modest builds + installs its CPM-bundled
# dftkit directly — no separate triqs_dftkit package, no clobber. This also
# installs the triqs_dftkit python module into this package. dftkit is Fortran,
# hence the fortran compiler in the build requirements.

mkdir build
cd build

# Specific setup for cross-compilation
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == "1" ]]; then
  # Openmpi
  export OPAL_PREFIX="$PREFIX"
fi

export CXXFLAGS="$CXXFLAGS -D_LIBCPP_DISABLE_AVAILABILITY"
source $PREFIX/share/triqs/triqsvars.sh

cmake ${CMAKE_ARGS} \
    -DCMAKE_CXX_COMPILER=${BUILD_PREFIX}/bin/$(basename ${CXX}) \
    -DCMAKE_C_COMPILER=${BUILD_PREFIX}/bin/$(basename ${CC}) \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DBuild_Deps=IfNotFound \
    ..

make -j${CPU_COUNT} VERBOSE=1

if [[ "${CONDA_BUILD_CROSS_COMPILATION}" != "1" ]]; then
  CTEST_OUTPUT_ON_FAILURE=1 ctest
fi

make install

# Rewrite any BUILD_PREFIX that leaked into the installed cmake targets file (the
# build prefix differs from the install prefix in every conda build). The file is
# absent for the pure-python apps, hence the file-existence guard.
tgt="${PREFIX}/lib/cmake/${PKG_NAME}/${PKG_NAME}-targets.cmake"
if [[ -f "$tgt" ]]; then
  sed "s|$BUILD_PREFIX|$PREFIX|g" "$tgt" > tmp_file
  cp tmp_file "$tgt"
fi
