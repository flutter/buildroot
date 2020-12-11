#!/usr/bin/python
# Copyright (c) 2015 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import argparse
import errno
import sys
import os
import subprocess

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
  args = parser.parse_args()

  path = subprocess.check_output(['/usr/bin/env', 'xcode-select', '-p']).strip()
  path = os.path.join(path, "Toolchains", "XcodeDefault.xctoolchain")
  assert os.path.exists(path)

  if args.symlink:
    mkdir_p(args.symlink)
    symlink_target = os.path.join(args.symlink, os.path.basename(path))
    if not os.path.exists(symlink_target):
      os.symlink(path, symlink_target)
    path = symlink_target

  print(path)

if __name__ == '__main__':
  sys.exit(main(sys.argv))
