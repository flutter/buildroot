#!/usr/bin/env python
# Copyright 2018 The Dart project authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Usage: tools/dart/dart_roll_helper.py [--create_commit] dart_sdk_revision
#
# This script automates the Dart SDK roll steps, including:
#   - Updating the Dart revision in DEPS
#   - Updating the Dart dependencies in DEPS
#   - Syncing dependencies with 'gclient sync'
#   - Generating GN files for relevant engine configurations
#   - Building relevant engine configurations
#   - Running tests in 'example/flutter_gallery' and 'packages/flutter'
#   - Launching flutter_gallery in release and debug mode
#   - Running license.sh and updating license files in
#     'flutter/ci/licenses_golden'
#   - Generating a commit with relevant Dart SDK commit logs (optional)
#
# Requires the following environment variables to be set:
#   - FLUTTER_HOME: the absolute path to the 'flutter' directory
#   - ENGINE_HOME: the absolute path to the 'engine/src' directory
#   - DART_SDK_HOME: the absolute path to the root of a Dart SDK project

import argparse
import datetime
import fileinput
import os
import shutil
import subprocess
import sys

FLUTTER_HOME = os.environ['FLUTTER_HOME']
ENGINE_HOME = os.environ['ENGINE_HOME']
DART_SDK_HOME = os.environ['DART_SDK_HOME']
UPDATE_DART_DEPS = ENGINE_HOME + 'tools/dart/create_updated_flutter_deps.py'
ENGINE_GOLDEN_LICENSES = ENGINE_HOME + 'flutter/ci/licenses_golden/'
ENGINE_LICENSE_SCRIPT = ENGINE_HOME + 'flutter/ci/licenses.sh'
FLUTTER_GALLERY = FLUTTER_HOME + 'examples/flutter_gallery'
PACKAGE_FLUTTER = FLUTTER_HOME + 'packages/flutter'
FLUTTER_DEPS_PATH = 'flutter/DEPS'
DART_REVISION_ENTRY = 'dart_revision'
FLUTTER_RUN = ['flutter', 'run']
FLUTTER_TEST = ['flutter', 'test']

original_revision = ''
updated_revision = ''

def print_status(msg):
  CGREEN = '\033[92m'
  CEND = '\033[0m'
  print(CGREEN + '[STATUS] ' + msg + CEND)

def update_dart_revision(dart_revision):
  global original_revision
  print_status('Updating Dart revision to {}'.format(dart_revision))
  content = get_deps()
  for idx, line in enumerate(content):
    if DART_REVISION_ENTRY in line:
      original_revision = line.strip().split(' ')[1][1:-2]
      content[idx] = "  'dart_revision': '" + dart_revision + "',\n"
      break
  write_deps(content)

def gclient_sync():
  print_status('Running gclient sync')
  p = subprocess.Popen(['gclient', 'sync'], cwd=ENGINE_HOME)
  p.wait()

def get_updated_deps():
  return subprocess.check_output([UPDATE_DART_DEPS])

def get_deps():
  with open(ENGINE_HOME + FLUTTER_DEPS_PATH, 'r') as f:
    content = f.readlines()
  return content

def update_deps():
  print_status('Updating Dart dependencies')
  content = get_deps()
  updateddartdeps = get_updated_deps()

  newcontent = []
  dartrevisionseen = False
  skipblankline = True

  for idx, line in enumerate(content):
    if not dartrevisionseen or skipblankline:
      newcontent.append(line)

      # Find the line with 'dart_revision'
      if DART_REVISION_ENTRY in line:
        dartrevisionseen = True
        newcontent.append('\n')
        newcontentstr = ''.join(newcontent)
        newcontentstr += updateddartdeps
        newcontent = newcontentstr.splitlines(True)
      elif dartrevisionseen:
        # Handle the blank line after 'dart_revision'
        skipblankline = False
    else:
      # Skip over the rest of the 'dart_*' deps and copy in the new ones.
      if not 'dart' in line:
        newcontent = newcontent + content[idx + 1:]
        break

  write_deps(newcontent)


def write_deps(newdeps):
  with open(ENGINE_HOME + FLUTTER_DEPS_PATH, 'w') as f:
    f.write(''.join(newdeps))

def run_gn():
  print_status('Generating build files')
  common = ['flutter/tools/gn', '--goma']
  debug = ['--runtime-mode=debug']
  profile = ['--runtime-mode=profile']
  release = ['--runtime-mode=release']
  runtime_modes = [debug, profile, release]
  unopt = ['--unoptimized']
  android = ['--android']

  for mode in runtime_modes:
    p = subprocess.Popen(common + android + unopt + mode, cwd=ENGINE_HOME)
    q = subprocess.Popen(common + android + mode, cwd=ENGINE_HOME)
    host = common[:]
    if set(mode) == set(debug):
      host += unopt
    r = subprocess.Popen(host + mode, cwd=ENGINE_HOME)
    p.wait()
    q.wait()
    r.wait()

def build():
  print_status('Building Flutter engine')
  command = ['ninja', '-j1000']
  configs = [
    'out/host_debug_unopt',
    'out/host_release',
    'out/host_profile',
    'out/android_debug_unopt',
    'out/android_debug',
    'out/android_profile_unopt',
    'out/android_profile',
    'out/android_release_unopt',
    'out/android_release'
  ]
  for config in configs:
    p = subprocess.Popen(command + ['-C', config], cwd=ENGINE_HOME)
    p.wait()

def run_tests():
  print_status('Running tests in packages/flutter')
  p = subprocess.Popen(FLUTTER_TEST + ['--local-engine=host_debug'],
                       cwd=PACKAGE_FLUTTER)
  p.wait()
  print_status('Running tests in examples/flutter_gallery')
  p = subprocess.Popen(FLUTTER_TEST + ['--local-engine=host_debug'],
                       cwd=FLUTTER_GALLERY);
  p.wait()

def run_hot_reload_configurations():
  print_status('Running flutter gallery release')
  p = subprocess.Popen(FLUTTER_RUN + ['--release', '--local-engine=android_release'],
                       cwd=FLUTTER_GALLERY)
  p.wait()
  print_status('Running flutter gallery debug')
  p = subprocess.Popen(FLUTTER_RUN + ['--local-engine=android_debug_unopt'],
                       cwd=FLUTTER_GALLERY)
  p.wait()

def update_licenses():
  print_status('Updating Flutter licenses')
  p = subprocess.Popen([ENGINE_LICENSE_SCRIPT], cwd=ENGINE_HOME)
  p.wait()
  LICENSE_SCRIPT_OUTPUT = 'out/license_script_output/'
  src_files = os.listdir(LICENSE_SCRIPT_OUTPUT)
  for f in src_files:
    path = os.path.join(LICENSE_SCRIPT_OUTPUT, f)
    if os.path.isfile(path):
      shutil.copy(path, ENGINE_GOLDEN_LICENSES)

def get_commit_range(start, finish):
  range_str = '{}...{}'.format(start, finish)
  command = ['git', 'log', '--oneline', range_str]
  orig_dir = os.getcwd()
  os.chdir(DART_SDK_HOME)
  result = subprocess.check_output(command)
  os.chdir(orig_dir)
  return result

def git_commit():
  global original_revision
  global updated_revision

  print_status('Committing Dart SDK roll')
  ENGINE_FLUTTER = ENGINE_HOME + 'flutter'
  current_date = datetime.date.today()
  sdk_log = get_commit_range(original_revision, updated_revision)
  commit_msg = 'Dart SDK roll for {}\n\n'.format(current_date)
  commit_msg += sdk_log
  commit_cmd = ['git', 'commit', '-a', '-m', commit_msg]
  p = subprocess.Popen(commit_cmd, cwd=ENGINE_FLUTTER)
  p.wait()


def main():
  global updated_revision

  parser = argparse.ArgumentParser(description='Automate most Dart SDK roll tasks.')
  parser.add_argument('dart_sdk_revision', help='Target Dart SDK revision')
  parser.add_argument('--create_commit', action='store_true',
                      help='Create the engine commit with Dart SDK commit log')
  parser.add_argument('--no_test', action='store_true',
                      help='Skip running tests and hot reload configurations')
  parser.add_argument('--no_update_licenses', action='store_true',
                      help='Skip updating licenses')
  args = parser.parse_args()
  updated_revision = args.dart_sdk_revision

  print_status('Starting Dart SDK roll')
  update_dart_revision(updated_revision)
  gclient_sync()
  update_deps()
  gclient_sync()
  run_gn()
  build()
  if not args.no_test:
    run_tests()
    run_hot_reload_configurations()
  if not args.no_update_licenses:
    update_licenses()
  if args.create_commit:
    git_commit()
  print_status('Dart SDK roll complete!')

if __name__ == '__main__':
  main()
