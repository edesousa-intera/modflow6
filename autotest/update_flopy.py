import os
import shutil
import subprocess
import importlib
from contextlib import contextmanager

import flopy

flopypth = flopy.__path__[0]
print("flopy is installed in {}".format(flopypth))


@contextmanager
def cwd(path):
    oldpwd = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(oldpwd)


def test_delete_mf6():
    pth = os.path.join(flopypth, "mf6", "modflow")
    files = [
        entry
        for entry in os.listdir(pth)
        if os.path.isfile(os.path.join(pth, entry))
    ]
    delete_files(files, pth, exclude="mfsimulation.py")


def test_delete_dfn():
    pth = os.path.join(flopypth, "mf6", "data", "dfn")
    files = [
        entry
        for entry in os.listdir(pth)
        if os.path.isfile(os.path.join(pth, entry))
    ]
    delete_files(files, pth, exclude="flopy.dfn")


def test_copy_dfn():
    pth0 = os.path.join("..", "doc", "mf6io", "mf6ivar", "dfn")
    files = [
        entry
        for entry in os.listdir(pth0)
        if os.path.isfile(os.path.join(pth0, entry))
    ]
    pth1 = os.path.join(flopypth, "mf6", "data", "dfn")
    for fn in files:
        ext = os.path.splitext(fn)[1].lower()
        if "dfn" in ext:
            fpth0 = os.path.join(pth0, fn)
            fpth1 = os.path.join(pth1, fn)
            print('copying {} from "{}" to "{}"'.format(fn, pth0, pth1))
            shutil.copyfile(fpth0, fpth1)


def test_create_packages():
    # get list of files in mf6/modflow
    pth = os.path.join(flopypth, "mf6", "modflow")
    list_files(pth)

    pth = os.path.join(flopypth, "mf6", "utils")
    fn = "createpackages.py"

    # determine if createpackages.py exists
    fpth = os.path.join(pth, fn)
    print('testing if "{}" exists'.format(fpth))
    exist = os.path.isfile(fpth)
    assert exist, '"{}" does not exist'.format(fpth)

    # run createrpackages.py script
    print("running...{}".format(fn))
    cmd = ["python", fn]
    buff, ierr = run_command(cmd, pth)
    assert ierr == 0, "could not run {}".format(fn)
    print("successfully ran...{}".format(fn))

    # reload flopy
    print("reloading flopy")
    importlib.reload(flopy)

    # get updated list of files in mf6/modflow
    pth = os.path.join(flopypth, "mf6", "modflow")
    list_files(pth)


def list_files(pth, exts=["py"]):
    print("\nLIST OF FILES IN {}".format(pth))
    files = [
        entry
        for entry in os.listdir(pth)
        if os.path.isfile(os.path.join(pth, entry))
    ]
    idx = 0
    for fn in files:
        ext = os.path.splitext(fn)[1][1:].lower()
        if ext in exts:
            idx += 1
            print("    {:5d} - {}".format(idx, fn))
    return


def delete_files(files, pth, allow_failure=False, exclude=None):
    if exclude is None:
        exclude = []
    else:
        if not isinstance(exclude, list):
            exclude = [exclude]

    for fn in files:
        if fn in exclude:
            continue
        fpth = os.path.join(pth, fn)
        try:
            print("removing...{}".format(fn))
            os.remove(fpth)
        except:
            print("could not remove...{}".format(fn))
            if not allow_failure:
                return False
    return True


def run_command(argv, pth, timeout=10):
    with subprocess.Popen(
        argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=pth
    ) as process:
        try:
            output, unused_err = process.communicate(timeout=timeout)
            buff = output.decode("utf-8")
            ierr = process.returncode
        except subprocess.TimeoutExpired:
            process.kill()
            output, unused_err = process.communicate()
            buff = output.decode("utf-8")
            ierr = 100
        except:
            output, unused_err = process.communicate()
            buff = output.decode("utf-8")
            ierr = 101

    return buff, ierr


def main():
    # write message
    tnam = os.path.splitext(os.path.basename(__file__))[0]
    msg = "Running {} test".format(tnam)
    print(msg)

    print("deleting existing MODFLOW 6 FloPy files")
    test_delete_mf6()
    print("deleting existing MODFLOW 6 dfn files")
    test_delete_dfn()
    print("copying MODFLOW 6 repo dfn files")
    test_copy_dfn()
    print("creating MODFLOW 6 packages from repo dfn files")
    test_create_packages()

    return


if __name__ == "__main__":
    print("standalone run of {}".format(os.path.basename(__file__)))

    # run main routine
    main()
