# Copyright 2014 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Helper script for GN to run an arbitrary binary. See compiled_action.gni.

Run with:
  python gn_run_binary.py <binary_name> [args ...]
"""

import platform
import sys
import subprocess


args = []
basearg = 1
if sys.argv[1] == "--time":
  basearg = 2
  if (platform.system() == "Linux"):
    args += ["/usr/bin/time", "-v"]
  elif (platform.system() == "Darwin"):
    args += ["/usr/bin/time", "-l"]

# This script is designed to run binaries produced by the current build. We
# always prefix it with "./" to avoid picking up system versions that might
# also be on the path.
path = './' + sys.argv[basearg]

# The rest of the arguements are passed directly to the executable.
args += [path] + sys.argv[basearg + 1:]

try:
  subprocess.check_output(args, stderr=subprocess.STDOUT)
except subprocess.CalledProcessError as ex:
  print("Command failed: " + ' '.join(args))
  print("exitCode: " + str(ex.returncode))
  print(ex.output.decode('utf-8', errors='replace'))

  # For --time'd executions do another control run to confirm failures.
  # This is to help troubleshoot https://github.com/flutter/flutter/issues/154437.
  if sys.argv[1] == "--time":
    try:
      subprocess.check_output(args, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as ex:
      print("2nd coming Command failed: " + ' '.join(args))
      print("2nd coming exitCode: " + str(ex.returncode))
      print(ex.output.decode('utf-8', errors='replace'))

  sys.exit(ex.returncode)
