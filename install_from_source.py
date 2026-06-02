#!/usr/bin/env python3
"""
Clone, build and INSTALL the TRIQS Summer School 2026 software stack FROM SOURCE
(no conda), pinned to the exact git commits used at the school (the same commits
the `triqs-summer-school` conda channel is built from).

Inspired by triqs/packaging/clone_archive_and_install.py, but every repository is
pinned to a fixed commit so the build reproduces the school's pre-release of TRIQS 4.0.

Prefer the conda packages (see installation.md) unless you specifically need a source
build. This script is the fallback for environments where conda is not an option.

Requirements: git, CMake >= 3.20, a C++20 compiler, MPI, HDF5, BLAS/LAPACK, FFTW, a
Fortran compiler (for triqs_modest / dmftproj), and Python >= 3.10 with NumPy / SciPy /
mpi4py. Dependencies (cppdlr, nda, h5, ...) are fetched at configure time, so network
access is required during the build.

Examples:
    # build the whole stack into ~/triqs_school using 8 cores
    python install_from_source.py --prefix ~/triqs_school -j 8

    # only triqs + cthyb, skipping the test suites
    python install_from_source.py -j 8 --no-tests triqs cthyb
"""

import argparse
import os
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

# Build order matters: triqs first, then the applications (each links the installed
# triqs). Pure-python apps still build through CMake (TRIQS app layout). Note: ctint,
# dft_tools and solid_dmft were NOT part of the school channel and are omitted here.
SCHOOL_REPOS = OrderedDict([
    ("triqs",        {"url": "https://github.com/TRIQS/triqs.git",        "commit": "18fb9558a8378be412d5c8516d88d6d478a94fff"}),
    ("cthyb",        {"url": "https://github.com/TRIQS/cthyb.git",        "commit": "85466c825c684e5ee79d015fd383d16011040cdb"}),
    ("ctseg",        {"url": "https://github.com/TRIQS/ctseg.git",        "commit": "790d8d91ec0f71408d7ab945d8504706e13f43b0"}),
    ("tprf",         {"url": "https://github.com/TRIQS/tprf.git",         "commit": "dd7586ed6f4be318528de728b7f48955797f225e"}),
    ("hubbardI",     {"url": "https://github.com/TRIQS/hubbardI.git",     "commit": "90f6198d082fa8a578b0915b318295b8e8b68d6b"}),
    ("hartree_fock", {"url": "https://github.com/TRIQS/hartree_fock.git", "commit": "0a6923ed3a390094070d4d924b606df521d05c96"}),
    ("maxent",       {"url": "https://github.com/TRIQS/maxent.git",       "commit": "ed47c9b3a3e4f3c77b29864bf35b6c4ccc4e8118"}),
    ("modest",       {"url": "https://github.com/TRIQS/modest.git",       "commit": "5936a266ed3a664148f6747d54f26fcc81a6c126"}),
])

SCHOOL_VERSION = "4.0.0.school2026"

# Known-failing DLR tests in this pre-release snapshot, mirrored from the conda
# recipes (recipes/<pkg>/recipe/build.sh). At these pinned commits the DLR path
# is understood to be broken; these tests are run NON-blocking (everything else
# stays strict and still gates the build) so a source build behaves like the
# conda build. Keep in sync with the recipe `dlr_re` regexes. ctest -E/-R regex.
KNOWN_DLR_FAILURES = {
    "cthyb": r"^Py_solve_generic$",
    "ctseg": r"^Py_solve_generic_dlr",
    "tprf":  r"(_dlr$|compare_dlr_and_direct|dlr_eliashberg_solver|test_tpsc_improved_bubble|test_tpsc_plus_Sigma)",
}


def run(cmd, **kwargs):
    """Run a command, echoing it, and abort the script on failure."""
    print("  $", " ".join(str(c) for c in cmd))
    subprocess.run(cmd, check=True, **kwargs)


def clone_pinned(name, src_dir):
    """Fetch exactly the pinned commit of `name` into `src_dir`."""
    info = SCHOOL_REPOS[name]

    def fetch_and_checkout():
        # GitHub allows fetching a bare SHA; --depth 1 keeps it light.
        run(["git", "-C", str(src_dir), "fetch", "-q", "--depth", "1", "origin", info["commit"]])
        run(["git", "-C", str(src_dir), "checkout", "-q", "--detach", "FETCH_HEAD"])

    if (src_dir / ".git").exists():
        head = subprocess.run(["git", "-C", str(src_dir), "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        if head == info["commit"]:
            print(f"[{name}] already at pinned {info['commit'][:12]} -- reusing")
        else:
            print(f"[{name}] checkout {head[:12]} != pinned {info['commit'][:12]} -- re-fetching")
            fetch_and_checkout()
    else:
        print(f"[{name}] fetching {info['commit'][:12]} from {info['url']}")
        src_dir.mkdir(parents=True, exist_ok=True)
        run(["git", "init", "-q", str(src_dir)])
        run(["git", "-C", str(src_dir), "remote", "add", "origin", info["url"]])
        fetch_and_checkout()
    # TRIQS 4.0 carries no git submodules (C++ deps come via CPM at configure
    # time), so this is normally a no-op -- kept in case a pinned repo ever does.
    run(["git", "-C", str(src_dir), "submodule", "update", "--init", "--recursive", "--depth", "1"])


def build_and_install(name, src_dir, build_dir, prefix, ncores, run_tests):
    """Configure, build, test and install one repository into `prefix`."""
    print(f"[{name}] building -> {prefix}")
    # triqs must build+install the C++ cores (nda/h5/itertools/...) itself, so it
    # keeps external_dependency()'s default (Build_Deps=Always); the apps reuse
    # those installed copies via IfNotFound. Pin Python_EXECUTABLE so the build
    # targets the same interpreter whose version we use for PYTHONPATH below.
    build_deps = "Always" if name == "triqs" else "IfNotFound"
    run(["cmake", "-B", str(build_dir), "-S", str(src_dir),
         f"-DCMAKE_INSTALL_PREFIX={prefix}",
         "-DCMAKE_BUILD_TYPE=Release",
         f"-DPython_EXECUTABLE={sys.executable}",
         f"-DBuild_Deps={build_deps}"])
    run(["cmake", "--build", str(build_dir), "-j", str(ncores)])
    if run_tests:
        dlr_re = KNOWN_DLR_FAILURES.get(name)
        if dlr_re:
            # Strict on everything except the known DLR failures ...
            run(["ctest", "--test-dir", str(build_dir), "-j", str(ncores),
                 "--output-on-failure", "-E", dlr_re])
            # ... then run the known DLR test(s) non-blocking, like the recipes.
            print(f"  $ ctest -R {dlr_re}  (known DLR failures: non-blocking)")
            rc = subprocess.run(["ctest", "--test-dir", str(build_dir),
                                 "--output-on-failure", "-R", dlr_re]).returncode
            if rc != 0:
                print(f"  [warning] {name}: ignoring known DLR test failure(s) matching {dlr_re}")
        else:
            run(["ctest", "--test-dir", str(build_dir), "-j", str(ncores), "--output-on-failure"])
    run(["cmake", "--install", str(build_dir)])


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter, allow_abbrev=False)
    parser.add_argument("repos", nargs="*", metavar="REPO",
                        help=f"subset to build, in dependency order (default: all). "
                             f"Choices: {', '.join(SCHOOL_REPOS)}")
    parser.add_argument("-d", "--dir", default="triqs_school_src",
                        help="working directory for clones + build trees (default: ./triqs_school_src)")
    parser.add_argument("-p", "--prefix",
                        help="CMake install prefix (default: <dir>/install)")
    parser.add_argument("-j", "--ncores", type=int, default=1,
                        help="parallel build/test jobs (default: 1)")
    parser.add_argument("--no-tests", action="store_true", help="skip the ctest suites")
    parser.add_argument("--clone-only", action="store_true", help="clone the pinned sources, do not build")
    args = parser.parse_args()

    selected = args.repos or list(SCHOOL_REPOS)
    unknown = [r for r in selected if r not in SCHOOL_REPOS]
    if unknown:
        parser.error(f"unknown repo(s): {', '.join(unknown)}. Choices: {', '.join(SCHOOL_REPOS)}")
    # Always build in the canonical (dependency) order regardless of arg order.
    selected = [r for r in SCHOOL_REPOS if r in selected]

    work = Path(args.dir).resolve()
    prefix = Path(args.prefix).resolve() if args.prefix else work / "install"
    print(f"School version : {SCHOOL_VERSION}")
    print(f"Work directory : {work}")
    print(f"Install prefix : {prefix}")
    print(f"Repositories   : {', '.join(selected)}\n")

    for name in selected:
        clone_pinned(name, work / f"{name}.src")

    if args.clone_only:
        print("\nClone-only requested -- stopping before build.")
        return

    # Make the freshly installed triqs discoverable to the apps that follow.
    # prepend() keeps an existing value but avoids a trailing separator (an empty
    # PATH entry would add the cwd to the import / cmake search path).
    def prepend(var, value):
        old = os.environ.get(var, "")
        os.environ[var] = value + os.pathsep + old if old else value

    py = f"{sys.version_info.major}.{sys.version_info.minor}"
    os.environ["TRIQS_ROOT"] = str(prefix)
    prepend("PYTHONPATH", f"{prefix}/lib/python{py}/site-packages")
    prepend("CMAKE_PREFIX_PATH", str(prefix))

    for name in selected:
        build_and_install(name, work / f"{name}.src", work / f"{name}.build",
                          prefix, args.ncores, run_tests=not args.no_tests)
        print("-" * 50)

    print(f"\nDone. Activate the build with:\n    source {prefix}/share/triqs/triqsvars.sh")


if __name__ == "__main__":
    main()
