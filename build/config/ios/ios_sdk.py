# Copyright 2014 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import argparse
import errno
import os
import subprocess
import sys

# This script returns the path to the SDK of the given type. Pass the type of
# SDK you want, which is typically 'iphone' or 'iphonesimulator'.

def mkdir_p(path):
  try:
    os.makedirs(path)
  except OSError as exc:
    if exc.errno == errno.EEXIST and os.path.isdir(path):
      pass
    else:
      raise


def main(argv):
  parser = argparse.ArgumentParser()
  parser.add_argument('--symlink',
                      help='Whether to create a symlink in the buildroot to the SDK.')
  parser.add_argument('--sdk',
                      choices=['iphone', 'iphonesimulator'],
                      help='Which SDK to find.')
  args = parser.parse_args()

  command =  [
    'xcodebuild',
    '-version',
    '-sdk',
    args.sdk,
    'Path'
  ]

  sdk_output = subprocess.check_output(command).strip()
  if args.symlink:
    mkdir_p(args.symlink)
    symlink_target = os.path.join(args.symlink, os.path.basename(sdk_output))
    if not os.path.exists(symlink_target):
      os.symlink(sdk_output, symlink_target)
    sdk_output = symlink_target

  print(sdk_output)
  return 0

if __name__ == '__main__':
  if sys.platform != 'darwin':
    raise Exception('This script only runs on Mac')
  sys.exit(main(sys.argv))
