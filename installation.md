# Installing the TRIQS Summer School 2026 software

These are the **exact** TRIQS 4.0 pre-release packages used at the 2026 summer school,
published as ready-to-use conda binaries on the
[`triqs-summer-school`](https://anaconda.org/triqs-summer-school) channel. The uniform
version label is `4.0.0.school2026`.

> **Supported platforms:** Linux (`linux-64`) and Apple-Silicon macOS (`osx-arm64`).
> Intel Macs (`osx-64`) are **not** supported — install on a Linux machine instead, or
> build from source (see the last section).

The steps below are self-contained: start from a machine with no conda and you end with a
working `school` environment.

## 1. Install Miniforge (conda)

Miniforge is the community conda installer that uses the conda-forge channel by default.
Get the installer for your platform from the conda-forge download page —
**<https://conda-forge.org/download/>** — and run it (accept the defaults). Equivalently,
from a terminal (this fetches the same installer the download page links to):

```bash
# macOS (Apple Silicon) or Linux — selects the right installer automatically
curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
bash "Miniforge3-$(uname)-$(uname -m).sh" -b
```

Initialise conda for your shell:

```bash
~/miniforge3/bin/conda init "$(basename "$SHELL")"
```

Then **close this terminal and open a new one** — `conda` will now be on your `PATH` and
the prompt will show `(base)`. Confirm it works:

```bash
conda --version
```

> Already have Miniforge / Miniconda / Mambaforge? Skip this step. Avoid the Anaconda
> Distribution's `defaults` channel — mixing it with conda-forge can break the solve; these
> instructions use conda-forge only.

## 2. Install the school software set

```bash
conda create -n school -c triqs-summer-school -c conda-forge triqs-all
conda activate school
```

This downloads a few hundred MB and the first solve can take a few minutes — let it finish.

`triqs-all` is a metapackage that pulls in the whole school stack: `triqs`, `triqs_cthyb`,
`triqs_ctseg`, `triqs_tprf`, `triqs_maxent`, `triqs_hubbardI`, `triqs_hartree_fock`, and
`triqs_modest` (which also provides `dmftproj`/`triqs_dftkit`).

### Pin a specific MPI / Python (optional)

We ship `mpich` and `openmpi` builds for Python 3.12/3.13/3.14. The solver picks a
consistent combination by default; to choose one explicitly:

```bash
conda create -n school -c triqs-summer-school -c conda-forge triqs-all "openmpi" python=3.13
```

## 3. Verify

```bash
conda activate school
python -c "import triqs, triqs_cthyb, triqs_ctseg, triqs_dftkit, triqs_modest, \
triqs_tprf, triqs_maxent, triqs_hubbardI, triqs_hartree_fock; print('school stack OK')"
```

`conda list` should show every package at version `4.0.0.school2026` from channel
`triqs-summer-school`.

## 4. Get the tutorials and start JupyterLab

The hands-on material lives in the [TRIQS/tutorials](https://github.com/TRIQS/tutorials)
repository. Use the **`unstable`** branch — it matches this TRIQS 4.0 pre-release (there is
no `4.0.x` branch yet). With the `school` environment active, add JupyterLab and clone the
tutorials:

```bash
conda activate school
conda install -c conda-forge jupyterlab     # the notebook interface
git clone -b unstable https://github.com/TRIQS/tutorials.git
```

Then launch JupyterLab from inside the clone — it opens in your browser:

```bash
cd tutorials
jupyter lab
```

Open any `.ipynb` and select the **Python 3** kernel (it is the `school` env's interpreter,
so `import triqs` already works). Stop the server with `Ctrl-C` in the terminal.

## 5. Upgrading to the official TRIQS 4.0 release

These are **pre-release** packages. The official **TRIQS 4.0** is expected on conda-forge
around **early July 2026**. Once it is out, the robust way to move over is a **fresh
environment** built purely from conda-forge:

```bash
conda create -n triqs -c conda-forge triqs triqs_cthyb triqs_ctseg triqs_tprf \
    triqs_maxent triqs_hubbardi triqs_hartree_fock
conda activate triqs
```

A fresh environment is the recommended path. **In-place `conda update` does not work**
here: the `triqs-all` metapackage exact-pins every component to `==4.0.0.school2026`, so
while it is installed it actively holds the whole stack at the school version (and
conda-forge ships no `triqs-all` to update to). If you must upgrade in place rather than
recreate, first drop the metapackage and then update against conda-forge:

```bash
conda remove triqs-all          # release the ==4.0.0.school2026 pins
conda update -c conda-forge --all
```

Note that some packages (notably `triqs_maxent`) are versioned independently on
conda-forge and may still not move cleanly, so when in doubt prefer the fresh environment.

## 6. Build from source (alternative)

If you cannot use conda (e.g. on an HPC cluster with a custom toolchain, or an Intel Mac),
`install_from_source.py` clones, builds and installs the **same pinned commits** from source:

```bash
python install_from_source.py --prefix ~/triqs_school -j 8
source ~/triqs_school/share/triqs/triqsvars.sh
```

Requires a C++20 compiler, CMake ≥ 3.20, an MPI implementation, HDF5, BLAS/LAPACK, FFTW,
Python ≥ 3.10 with NumPy/SciPy/mpi4py, and network access (dependencies are fetched at
configure time). Run `python install_from_source.py --help` for options.
