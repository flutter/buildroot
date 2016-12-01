// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// See README in this directory for information on how this code is organised.

import 'dart:collection';
import 'dart:convert';
import 'dart:io' as system;

import 'filesystem.dart' as fs;
import 'licenses.dart';
import 'patterns.dart';


// REPOSITORY OBJECTS

abstract class RepositoryEntry {
  RepositoryEntry(this.parent, this.io);
  final RepositoryDirectory parent;
  final fs.IoNode io;
  String get name => io.name;
  String get libraryName;

  @override
  String toString() => io.fullName;
}

abstract class RepositoryFile extends RepositoryEntry {
  RepositoryFile(RepositoryDirectory parent, fs.File io) : super(parent, io);

  Iterable<License> get licenses;

  @override
  String get libraryName => parent.libraryName;

  @override
  fs.File get io => super.io;
}

abstract class RepositoryLicensedFile extends RepositoryFile {
  RepositoryLicensedFile(RepositoryDirectory parent, fs.File io) : super(parent, io);

  bool get isIncludedInBuildProducts => true; // this should be conservative, err on the side of "true" if you're not sure
}

class RepositorySourceFile extends RepositoryLicensedFile {
  RepositorySourceFile(RepositoryDirectory parent, fs.TextFile io) : super(parent, io);

  @override
  fs.TextFile get io => super.io;

  // file names that we are confident won't be included in the final build product
  static final RegExp _readmeNamePattern = new RegExp(r'\b_*(?:readme|contributing|patents)_*\b', caseSensitive: false);
  static final RegExp _buildTimePattern = new RegExp(r'^(?!.*gen$)(?:CMakeLists\.txt|(?:pkgdata)?Makefile(?:\.inc)?(?:\.am|\.in|)|configure(?:\.ac|\.in)?|config\.(?:sub|guess)|.+\.m4|install-sh|.+\.sh|.+\.bat|.+\.pyc?|.+\.pl|icu-configure|.+\.gypi?|.*\.gni?|.+\.mk|.+\.cmake|.+\.gradle|.+\.yaml|vms_make\.com|pom\.xml|\.project|source\.properties)$', caseSensitive: false);
  static final RegExp _docsPattern = new RegExp(r'^(?:INSTALL|NEWS|OWNERS|AUTHORS|ChangeLog(?:\.rst|\.[0-9]+)?|.+\.txt|.+\.md|.+\.log|.+\.css|.+\.1|doxygen\.config|.+\.spec(?:\.in)?)$', caseSensitive: false);
  static final RegExp _devPattern = new RegExp(r'^(?:codereview\.settings|.+\.~|.+\.~[0-9]+~)$', caseSensitive: false);
  static final RegExp _testsPattern = new RegExp(r'^(?:tj(?:bench|example)test\.(?:java\.)?in|example\.c)$', caseSensitive: false);

  @override
  bool get isIncludedInBuildProducts {
    return !io.name.contains(_readmeNamePattern)
        && !io.name.contains(_buildTimePattern)
        && !io.name.contains(_docsPattern)
        && !io.name.contains(_devPattern)
        && !io.name.contains(_testsPattern)
        && !_isShellScript;
  }

  static final RegExp _hashBangPattern = new RegExp(r'^#! *(?:/bin/sh|/bin/bash|/usr/bin/env +(?:python|bash))\b');

  bool get _isShellScript {
    return io.readString().startsWith(_hashBangPattern);
  }

  List<License> _licenses;

  @override
  Iterable<License> get licenses {
    if (_licenses != null)
      return _licenses;
    String contents;
    try {
      contents = io.readString();
    } on FormatException {
      print('non-UTF8 data in $io');
      system.exit(2);
    }
    _licenses = determineLicensesFor(contents, name, parent, origin: '$this');
    if (_licenses == null || _licenses.isEmpty) {
      _licenses = parent.nearestLicensesFor(name);
      if (_licenses == null || _licenses.isEmpty)
        throw 'file has no detectable license and no in-scope default license file';
    }
    _licenses.forEach((License license) => license.markUsed(io.fullName, libraryName));
    assert(_licenses != null && _licenses.isNotEmpty);
    return _licenses;
  }
}

class RepositoryBinaryFile extends RepositoryLicensedFile {
  RepositoryBinaryFile(RepositoryDirectory parent, fs.File io) : super(parent, io);

  @override
  fs.File get io => super.io;

  List<License> _licenses;

  @override
  List<License> get licenses {
    if (_licenses == null) {
      _licenses = parent.nearestLicensesFor(name);
      if (_licenses == null || _licenses.isEmpty)
        throw 'no license file found in scope for ${io.fullName}';
      _licenses.forEach((License license) => license.markUsed(io.fullName, libraryName));
    }
    return _licenses;
  }
}


// LICENSES

abstract class RepositoryLicenseFile extends RepositoryFile {
  RepositoryLicenseFile(RepositoryDirectory parent, fs.File io) : super(parent, io);

  List<License> licensesFor(String name);
  License licenseOfType(LicenseType type);
  License licenseWithName(String name);

  License get defaultLicense;
}

abstract class RepositorySingleLicenseFile extends RepositoryLicenseFile {
  RepositorySingleLicenseFile(RepositoryDirectory parent, fs.TextFile io, this.license)
    : super(parent, io);

  final License license;

  @override
  List<License> licensesFor(String name) {
    if (license != null)
      return <License>[license];
    return null;
  }

  @override
  License licenseWithName(String name) {
    if (this.name == name)
      return license;
    return null;
  }

  @override
  License get defaultLicense => license;

  @override
  Iterable<License> get licenses sync* { yield license; }
}

class RepositoryGeneralSingleLicenseFile extends RepositorySingleLicenseFile {
  RepositoryGeneralSingleLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : super(parent, io, new License.fromBodyAndName(io.readString(), io.name, origin: io.fullName));

  RepositoryGeneralSingleLicenseFile.fromLicense(RepositoryDirectory parent, fs.TextFile io, License license)
    : super(parent, io, license);

  @override
  License licenseOfType(LicenseType type) {
    if (type == license.type)
      return license;
    return null;
  }
}

class RepositoryApache4DNoticeFile extends RepositorySingleLicenseFile {
  RepositoryApache4DNoticeFile(RepositoryDirectory parent, fs.TextFile io)
    : super(parent, io, _parseLicense(io));

  @override
  License licenseOfType(LicenseType type) => null;

  static final RegExp _pattern = new RegExp(
    r'^(// ------------------------------------------------------------------\n'
    r'// NOTICE file corresponding to the section 4d of The Apache License,\n'
    r'// Version 2\.0, in this case for (?:.+)\n'
    r'// ------------------------------------------------------------------\n)'
    r'((?:.|\n)+)$',
    multiLine: false,
    caseSensitive: false
  );

  static bool consider(fs.TextFile io) {
    return io.readString().contains(_pattern);
  }

  static License _parseLicense(fs.TextFile io) {
    final Match match = _pattern.allMatches(io.readString()).single;
    assert(match.groupCount == 2);
    return new License.unique(match.group(2), LicenseType.apacheNotice, origin: io.fullName);
  }
}

class RepositoryLicenseRedirectFile extends RepositorySingleLicenseFile {
  RepositoryLicenseRedirectFile(RepositoryDirectory parent, fs.TextFile io, License license)
    : super(parent, io, license);

  @override
  License licenseOfType(LicenseType type) {
    if (type == license.type)
      return license;
    return null;
  }

  static RepositoryLicenseRedirectFile maybeCreateFrom(RepositoryDirectory parent, fs.TextFile io) {
    String contents = io.readString();
    License license = interpretAsRedirectLicense(contents, parent, origin: io.fullName);
    if (license != null)
      return new RepositoryLicenseRedirectFile(parent, io, license);
    return null;
  }
}

class RepositoryLicenseFileWithLeader extends RepositorySingleLicenseFile {
  RepositoryLicenseFileWithLeader(RepositoryDirectory parent, fs.TextFile io, RegExp leader)
    : super(parent, io, _parseLicense(io, leader));

  @override
  License licenseOfType(LicenseType type) => null;

  static License _parseLicense(fs.TextFile io, RegExp leader) {
    final String body = io.readString();
    final Match match = leader.firstMatch(body);
    if (match == null)
      throw 'failed to strip leader from $io\nleader: /$leader/\nbody:\n---\n$body\n---';
    return new License.fromBodyAndName(body.substring(match.end), io.name, origin: io.fullName);
  }
}

class RepositoryReadmeIjgFile extends RepositorySingleLicenseFile {
  RepositoryReadmeIjgFile(RepositoryDirectory parent, fs.TextFile io)
    : super(parent, io, _parseLicense(io));

  static final RegExp _pattern = new RegExp(
    r'Permission is hereby granted to use, copy, modify, and distribute this\n'
    r'software \(or portions thereof\) for any purpose, without fee, subject to these\n'
    r'conditions:\n'
    r'\(1\) If any part of the source code for this software is distributed, then this\n'
    r'README file must be included, with this copyright and no-warranty notice\n'
    r'unaltered; and any additions, deletions, or changes to the original files\n'
    r'must be clearly indicated in accompanying documentation\.\n'
    r'\(2\) If only executable code is distributed, then the accompanying\n'
    r'documentation must state that "this software is based in part on the work of\n'
    r'the Independent JPEG Group"\.\n'
    r'\(3\) Permission for use of this software is granted only if the user accepts\n'
    r'full responsibility for any undesirable consequences; the authors accept\n'
    r'NO LIABILITY for damages of any kind\.\n',
    caseSensitive: false
  );

  static License _parseLicense(fs.TextFile io) {
    String body = io.readString();
    if (!body.contains(_pattern))
      throw 'unexpected contents in IJG README';
    return new License.message(body, LicenseType.ijg, origin: io.fullName);
  }

  @override
  License licenseWithName(String name) {
    if (this.name == name)
      return license;
    return null;
  }

  @override
  License licenseOfType(LicenseType type) {
    return null;
  }
}

class RepositoryDartLicenseFile extends RepositorySingleLicenseFile {
  RepositoryDartLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : super(parent, io, _parseLicense(io));

  static final RegExp _pattern = new RegExp(
    r'^This license applies to all parts of Dart that are not externally\n'
    r'maintained libraries\. The external maintained libraries used by\n'
    r'Dart are:\n'
    r'\n'
    r'(?:.+\n)+'
    r'\n'
    r'The libraries may have their own licenses; we recommend you read them,\n'
    r'as their terms may differ from the terms below\.\n'
    r'\n'
    r'(Copyright (?:.|\n)+)$',
    caseSensitive: false
  );

  static License _parseLicense(fs.TextFile io) {
    final Match match = _pattern.firstMatch(io.readString());
    if (match == null || match.groupCount != 1)
      throw 'unexpected Dart license file contents';
    return new License.template(match.group(1), LicenseType.bsd, origin: io.fullName);
  }

  @override
  License licenseOfType(LicenseType type) {
    return null;
  }
}

class RepositoryLibPngLicenseFile extends RepositorySingleLicenseFile {
  RepositoryLibPngLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : super(parent, io, new License.blank(io.readString(), LicenseType.libpng, origin: io.fullName)) {
    _verifyLicense(io);
  }

  static void _verifyLicense(fs.TextFile io) {
    final String contents = io.readString();
    if (!contents.contains('COPYRIGHT NOTICE, DISCLAIMER, and LICENSE:') ||
        !contents.contains('png') ||
        !contents.contains('END OF COPYRIGHT NOTICE, DISCLAIMER, and LICENSE.'))
      throw 'unexpected libpng license file contents:\n----8<----$contents\n----<8----';
  }

  @override
  License licenseOfType(LicenseType type) {
    if (type == LicenseType.libpng)
      return license;
    return null;
  }
}

class RepositoryBlankLicenseFile extends RepositorySingleLicenseFile {
  RepositoryBlankLicenseFile(RepositoryDirectory parent, fs.TextFile io, String sanityCheck)
    : super(parent, io, new License.blank(io.readString(), LicenseType.unknown)) {
    _verifyLicense(io, sanityCheck);
  }

  static void _verifyLicense(fs.TextFile io, String sanityCheck) {
    final String contents = io.readString();
    if (!contents.contains(sanityCheck))
      throw 'unexpected file contents; wanted "$sanityCheck", but got:\n----8<----$contents\n----<8----';
  }

  @override
  License licenseOfType(LicenseType type) => null;
}

class RepositoryOkHttpLicenseFile extends RepositorySingleLicenseFile {
  RepositoryOkHttpLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : super(parent, io, _parseLicense(io));

  static final RegExp _pattern = new RegExp(
    r'^((?:.|\n)*)\n'
    r'Licensed under the Apache License, Version 2\.0 \(the "License"\);\n'
    r'you may not use this file except in compliance with the License\.\n'
    r'You may obtain a copy of the License at\n'
    r'\n'
    r'   (http://www\.apache\.org/licenses/LICENSE-2\.0)\n'
    r'\n'
    r'Unless required by applicable law or agreed to in writing, software\n'
    r'distributed under the License is distributed on an "AS IS" BASIS,\n'
    r'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied\.\n'
    r'See the License for the specific language governing permissions and\n'
    r'limitations under the License\.\n*$',
    caseSensitive: false
  );

  static License _parseLicense(fs.TextFile io) {
    final Match match = _pattern.firstMatch(io.readString());
    if (match == null || match.groupCount != 2)
      throw 'unexpected okhttp license file contents';
    return new License.fromUrl(match.group(2), origin: io.fullName);
  }

  @override
  License licenseOfType(LicenseType type) {
    if (type == LicenseType.libpng)
      return defaultLicense;
    return null;
  }
}

class RepositoryLibJpegTurboLicense extends RepositoryLicenseFile {
  RepositoryLibJpegTurboLicense(RepositoryDirectory parent, fs.TextFile io)
    : super(parent, io) {
    _parseLicense(io);
  }

  static final RegExp _pattern = new RegExp(
    r'libjpeg-turbo is covered by three compatible BSD-style open source licenses:\n'
    r'\n'
    r'- The IJG \(Independent JPEG Group\) License, which is listed in\n'
    r'  \[README\.ijg\]\(README\.ijg\)\n'
    r'\n'
    r'  This license applies to the libjpeg API library and associated programs\n'
    r'  \(any code inherited from libjpeg, and any modifications to that code\.\)\n'
    r'\n'
    r'- The Modified \(3-clause\) BSD License, which is listed in\n'
    r'  \[turbojpeg\.c\]\(turbojpeg\.c\)\n'
    r'\n'
    r'  This license covers the TurboJPEG API library and associated programs\.\n'
    r'\n'
    r'- The zlib License, which is listed in \[simd/jsimdext\.inc\]\(simd/jsimdext\.inc\)\n'
    r'\n'
    r'  This license is a subset of the other two, and it covers the libjpeg-turbo\n'
    r'  SIMD extensions\.\n'
  );

  static void _parseLicense(fs.TextFile io) {
    String body = io.readString();
    if (!body.contains(_pattern))
      throw 'unexpected contents in libjpeg-turbo LICENSE';
  }

  List<License> _licenses;

  @override
  List<License> get licenses {
    if (_licenses == null) {
      final RepositoryReadmeIjgFile readme = parent.getChildByName('README.ijg');
      final RepositorySourceFile main = parent.getChildByName('turbojpeg.c');
      final RepositoryDirectory simd = parent.getChildByName('simd');
      final RepositorySourceFile zlib = simd.getChildByName('jsimdext.inc');
      _licenses = <License>[];
      _licenses.add(readme.license);
      _licenses.add(main.licenses.single);
      _licenses.add(zlib.licenses.single);
    }
    return _licenses;
  }

  @override
  License licenseWithName(String name) {
    return null;
  }

  @override
  List<License> licensesFor(String name) {
    return licenses;
  }

  @override
  License licenseOfType(LicenseType type) {
    return null;
  }

  @override
  License get defaultLicense => null;
}

class RepositoryFreetypeLicenseFile extends RepositoryLicenseFile {
  RepositoryFreetypeLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : _target = _parseLicense(io), super(parent, io);

  static final RegExp _pattern = new RegExp(
    r"The  FreeType 2  font  engine is  copyrighted  work and  cannot be  used\n"
    r"legally  without a  software license\.   In  order to  make this  project\n"
    r"usable  to a vast  majority of  developers, we  distribute it  under two\n"
    r"mutually exclusive open-source licenses\.\n"
    r"\n"
    r"This means  that \*you\* must choose  \*one\* of the  two licenses described\n"
    r"below, then obey  all its terms and conditions when  using FreeType 2 in\n"
    r"any of your projects or products.\n"
    r"\n"
    r"  - The FreeType License, found in  the file `(FTL\.TXT)', which is similar\n"
    r"    to the original BSD license \*with\* an advertising clause that forces\n"
    r"    you  to  explicitly cite  the  FreeType  project  in your  product's\n"
    r"    documentation\.  All  details are in the license  file\.  This license\n"
    r"    is  suited  to products  which  don't  use  the GNU  General  Public\n"
    r"    License\.\n"
    r"\n"
    r"    Note that  this license  is  compatible  to the  GNU General  Public\n"
    r"    License version 3, but not version 2\.\n"
    r"\n"
    r"  - The GNU General Public License version 2, found in  `GPLv2\.TXT' \(any\n"
    r"    later version can be used  also\), for programs which already use the\n"
    r"    GPL\.  Note  that the  FTL is  incompatible  with  GPLv2 due  to  its\n"
    r"    advertisement clause\.\n"
    r"\n"
    r"The contributed BDF and PCF drivers come with a license similar  to that\n"
    r"of the X Window System\.  It is compatible to the above two licenses \(see\n"
    r"file src/bdf/README and src/pcf/README\)\.\n"
    r"\n"
    r"The gzip module uses the zlib license \(see src/gzip/zlib\.h\) which too is\n"
    r"compatible to the above two licenses\.\n"
    r"\n"
    r"The MD5 checksum support \(only used for debugging in development builds\)\n"
    r"is in the public domain\.\n"
    r"\n*"
    r"--- end of LICENSE\.TXT ---\n*$"
  );

  static String _parseLicense(fs.TextFile io) {
    final Match match = _pattern.firstMatch(io.readString());
    if (match == null || match.groupCount != 1)
      throw 'unexpected Freetype license file contents';
    return match.group(1);
  }

  final String _target;
  List<License> _targetLicense;

  void _warmCache() {
    _targetLicense ??= <License>[parent.nearestLicenseWithName(_target)];
  }

  @override
  List<License> licensesFor(String name) {
    _warmCache();
    return _targetLicense;
  }

  @override
  License licenseOfType(LicenseType type) => null;

  @override
  License licenseWithName(String name) => null;

  @override
  License get defaultLicense {
    _warmCache();
    return _targetLicense.single;
  }

  @override
  Iterable<License> get licenses sync* { }
}

class RepositoryIcuLicenseFile extends RepositoryLicenseFile {
  RepositoryIcuLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : _licenses = _parseLicense(io),
      super(parent, io);

  @override
  fs.TextFile get io => super.io;

  final List<License> _licenses;

  static final RegExp _pattern = new RegExp(
    r'^ICU License - ICU [0-9.]+ and later\n+'
    r' *COPYRIGHT AND PERMISSION NOTICE\n+'
    r'( *Copyright (?:.|\n)+?)\n+' // 1
    r' *___________________________________________________________________\n+'
    r'( *All trademarks and registered trademarks mentioned herein are the\n'
    r' *property of their respective owners\.)\n+' // 2
    r' *___________________________________________________________________\n+'
    r'Third-Party Software Licenses\n+'
    r' *This section contains third-party software notices and/or additional\n'
    r' *terms for licensed third-party software components included within ICU\n'
    r' *libraries\.\n+'
    r' *1\. Unicode Data Files and Software[ \n]+?'
    r' *COPYRIGHT AND PERMISSION NOTICE\n+'
    r'(Copyright (?:.|\n)+?)\n+' //3
    r' *2\. Chinese/Japanese Word Break Dictionary Data \(cjdict\.txt\)\n+'
    r' #    The Google Chrome software developed by Google is licensed under the BSD li\n?'
    r'cense\. Other software included in this distribution is provided under other licen\n?'
    r'ses, as set forth below\.\n'
    r' #\n'
    r'( #      The BSD License\n'
    r' #      http://opensource\.org/licenses/bsd-license\.php\n'
    r' # +Copyright(?:.|\n)+?)\n' // 4
    r' #\n'
    r' #\n'
    r' #      The word list in cjdict.txt are generated by combining three word lists l\n?'
    r'isted\n'
    r' #      below with further processing for compound word breaking\. The frequency i\n?'
    r's generated\n'
    r' #      with an iterative training against Google web corpora\.\n'
    r' #\n'
    r' #      \* Libtabe \(Chinese\)\n'
    r' #        - https://sourceforge\.net/project/\?group_id=1519\n'
    r' #        - Its license terms and conditions are shown below\.\n'
    r' #\n'
    r' #      \* IPADIC \(Japanese\)\n'
    r' #        - http://chasen\.aist-nara\.ac\.jp/chasen/distribution\.html\n'
    r' #        - Its license terms and conditions are shown below\.\n'
    r' #\n'
    r' #      ---------COPYING\.libtabe ---- BEGIN--------------------\n'
    r' #\n'
    r' # +/\*\n'
    r'( # +\* Copyrighy (?:.|\n)+?)\n' // yeah, that's a typo in the license. // 5
    r' # +\*/\n'
    r' #\n'
    r' # +/\*\n'
    r'( # +\* Copyright (?:.|\n)+?)\n' // 6
    r' # +\*/\n'
    r' #\n'
    r'( # +Copyright (?:.|\n)+?)\n' // 7
    r' #\n'
    r' # +---------------COPYING\.libtabe-----END-----------------------------------\n-\n'
    r' #\n'
    r' #\n'
    r' # +---------------COPYING\.ipadic-----BEGIN----------------------------------\n--\n'
    r' #\n'
    r'( # +Copyright (?:.|\n)+?)\n' // 8
    r' #\n'
    r' # +---------------COPYING\.ipadic-----END------------------------------------\n'
    r'\n'
    r' *3\. Lao Word Break Dictionary Data \(laodict\.txt\)\n'
    r'\n'
    r'( # +Copyright(?:.|\n)+?)\n' // 9
    r'\n'
    r' *4\. Burmese Word Break Dictionary Data \(burmesedict\.txt\)\n'
    r'\n'
    r'( # +Copyright(?:.|\n)+?)\n' // 10
    r'\n'
    r' *5\. Time Zone Database\n'
    r'((?:.|\n)+)$',
    multiLine: true,
    caseSensitive: false
  );

  static final RegExp _unexpectedHash = new RegExp(r'^.+ #', multiLine: true);
  static final RegExp _newlineHash = new RegExp(r' # ?');

  static String _dewrap(String s) {
    if (!s.startsWith(' # '))
      return s;
    if (s.contains(_unexpectedHash))
      throw 'ICU license file contained unexpected hash sequence';
    if (s.contains('\x2028'))
      throw 'ICU license file contained unexpected line separator';
    return s.replaceAll(_newlineHash, '\x2028').replaceAll('\n', '').replaceAll('\x2028', '\n');
  }

  static List<License> _parseLicense(fs.TextFile io) {
    final Match match = _pattern.firstMatch(io.readString());
    if (match == null)
      throw 'could not parse ICU license file';
    assert(match.groupCount == 11);
    if (match.group(11).contains(copyrightMentionPattern))
      throw 'unexpected copyright in ICU license file';
    final List<License> result = <License>[
      new License.fromBodyAndType(_dewrap('${match.group(1)}\n\n${match.group(2)}'), LicenseType.icu, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(3)), LicenseType.unknown, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(4)), LicenseType.bsd, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(5)), LicenseType.bsd, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(6)), LicenseType.bsd, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(7)), LicenseType.unknown, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(8)), LicenseType.unknown, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(9)), LicenseType.bsd, origin: io.fullName),
      new License.fromBodyAndType(_dewrap(match.group(10)), LicenseType.bsd, origin: io.fullName),
    ];
    return result;
  }

  @override
  List<License> licensesFor(String name) {
    return _licenses;
  }

  @override
  License licenseOfType(LicenseType type) {
    if (type == LicenseType.icu)
      return _licenses[0];
    throw 'tried to use ICU license file to find a license by type but type wasn\'t ICU';
  }

  @override
  License licenseWithName(String name) {
    throw 'tried to use ICU license file to find a license by name';
  }

  @override
  License get defaultLicense => _licenses[0];

  @override
  Iterable<License> get licenses => _licenses;
}

class RepositoryXdgMimeLicenseFile extends RepositoryLicenseFile {
  RepositoryXdgMimeLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : _licenses = _parseLicense(io),
      super(parent, io);

  @override
  fs.TextFile get io => super.io;

  final List<License> _licenses;

  static final RegExp _pattern = new RegExp(
    r'^Licensed under the Academic Free License version 2\.0 \(below\)\n*'
    r'Or under the following terms:\n+'
    r'This library is free software; you can redistribute it and/or\n'
    r'modify it under the terms of the GNU Lesser General Public\n'
    r'License as published by the Free Software Foundation; either\n'
    r'version (2) of the License, or \(at your option\) any later version\.\n+'
    r'This library is distributed in the hope that it will be useful,\n'
    r'but WITHOUT ANY WARRANTY; without even the implied warranty of\n'
    r'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE\. +See the GNU\n'
    r'Lesser General Public License for more details\.\n+'
    r'You should have received a copy of the (GNU Lesser) General Public\n'
    r'License along with this library; if not, write to the\n'
    r'Free Software Foundation, Inc\., 59 Temple Place - Suite 330,\n'
    r'Boston, MA 02111-1307, USA\.\n*'
    r'--------------------------------------------------------------------------------\n'
    r'Academic Free License v\. 2\.0\n'
    r'--------------------------------------------------------------------------------\n+'
    r'(This Academic Free License \(the "License"\) applies to (?:.|\n)*'
    r'This license is Copyright \(C\) 2003 Lawrence E\. Rosen\. All rights reserved\.\n'
    r'Permission is hereby granted to copy and distribute this license without\n'
    r'modification\. This license may not be modified without the express written\n'
    r'permission of its copyright owner\.\n*)$',
    multiLine: true,
    caseSensitive: false
  );

  static List<License> _parseLicense(fs.TextFile io) {
    final Match match = _pattern.firstMatch(io.readString());
    if (match == null)
      throw 'could not parse xdg_mime license file';
    assert(match.groupCount == 3);
    return <License>[
      new License.fromUrl('${match.group(2)}:${match.group(1)}', origin: io.fullName),
      new License.fromBodyAndType(match.group(3), LicenseType.afl, origin: io.fullName),
    ];
  }

  @override
  List<License> licensesFor(String name) {
    return <License>[_licenses[0]];
  }

  @override
  License licenseOfType(LicenseType type) {
    if (type == _licenses[0].type)
      return _licenses[0];
    if (type == _licenses[1].type)
      return _licenses[1];
    throw 'tried to use xdg_mime license file to find a license by type but type wasn\'t valid';
  }

  @override
  License licenseWithName(String name) {
    throw 'tried to use xdg_mime license file to find a license by name';
  }

  @override
  License get defaultLicense => _licenses[0];

  @override
  Iterable<License> get licenses => _licenses;
}

Iterable<List<int>> splitIntList(List<int> data, int boundary) sync* {
  int index = 0;
  List<int> getOne() {
    int start = index;
    int end = index;
    while ((end < data.length) && (data[end] != boundary))
      end += 1;
    end += 1;
    index = end;
    return data.sublist(start, end).toList();
  }
  while (index < data.length)
    yield getOne();
}

class RepositoryMultiLicenseNoticesForFilesFile extends RepositoryLicenseFile {
  RepositoryMultiLicenseNoticesForFilesFile(RepositoryDirectory parent, fs.File io)
    : _licenses = _parseLicense(io),
      super(parent, io);

  @override
  fs.File get io => super.io;

  final Map<String, License> _licenses;

  static Map<String, License> _parseLicense(fs.File io) {
    final Map<String, License> result = <String, License>{};
    // Files of this type should begin with:
    // "Notices for files contained in the"
    // ...then have a second line which is 60 "=" characters
    final List<List<int>> contents = splitIntList(io.readBytes(), 0x0A).toList();
    if (!ASCII.decode(contents[0]).startsWith('Notices for files contained in') ||
        ASCII.decode(contents[1]) != '============================================================\n')
      throw 'unrecognised syntax: ${io.fullName}';
    int index = 2;
    while (index < contents.length) {
      if (ASCII.decode(contents[index]) != 'Notices for file(s):\n')
        throw 'unrecognised syntax on line ${index + 1}: ${io.fullName}';
      index += 1;
      final List<String> names = <String>[];
      do {
        names.add(ASCII.decode(contents[index]));
        index += 1;
      } while (ASCII.decode(contents[index]) != '------------------------------------------------------------\n');
      index += 1;
      final List<List<int>> body = <List<int>>[];
      do {
        body.add(contents[index]);
        index += 1;
      } while (index < contents.length &&
               ASCII.decode(contents[index], allowInvalid: true) != '============================================================\n');
      index += 1;
      final List<int> bodyBytes = body.expand((List<int> line) => line).toList();
      String bodyText;
      try {
        bodyText = UTF8.decode(bodyBytes);
      } on FormatException {
        bodyText = LATIN1.decode(bodyBytes);
      }
      License license = new License.unique(bodyText, LicenseType.unknown, origin: io.fullName);
      for (String name in names) {
        if (result[name] != null)
          throw 'conflicting license information for $name in ${io.fullName}';
        result[name] = license;
      }
    }
    return result;
  }

  @override
  List<License> licensesFor(String name) {
    License license = _licenses[name];
    if (license != null)
      return <License>[license];
    return null;
  }

  @override
  License licenseOfType(LicenseType type) {
    throw 'tried to use multi-license license file to find a license by type';
  }

  @override
  License licenseWithName(String name) {
    throw 'tried to use multi-license license file to find a license by name';
  }

  @override
  License get defaultLicense {
    assert(false);
    throw '$this ($runtimeType) does not have a concept of a "default" license';
  }

  @override
  Iterable<License> get licenses => _licenses.values;
}

class RepositoryCxxStlDualLicenseFile extends RepositoryLicenseFile {
  RepositoryCxxStlDualLicenseFile(RepositoryDirectory parent, fs.TextFile io)
    : _licenses = _parseLicenses(io), super(parent, io);

  static final RegExp _pattern = new RegExp(
    r'^'
    r'==============================================================================\n'
    r'.+ License\n'
    r'==============================================================================\n'
    r'\n'
    r'The .+ library is dual licensed under both the University of Illinois\n'
    r'"BSD-Like" license and the MIT license\. +As a user of this code you may choose\n'
    r'to use it under either license\. +As a contributor, you agree to allow your code\n'
    r'to be used under both\.\n'
    r'\n'
    r'Full text of the relevant licenses is included below\.\n'
    r'\n'
    r'==============================================================================\n'
    r'((?:.|\n)+)\n'
    r'==============================================================================\n'
    r'((?:.|\n)+)'
    r'$'
  );

  static List<License> _parseLicenses(fs.TextFile io) {
    final Match match = _pattern.firstMatch(io.readString());
    if (match == null || match.groupCount != 2)
      throw 'unexpected dual license file contents';
    return <License>[
      new License.fromBodyAndType(match.group(1), LicenseType.bsd),
      new License.fromBodyAndType(match.group(2), LicenseType.mit),
    ];
  }

  List<License> _licenses;

  @override
  List<License> licensesFor(String name) {
    return _licenses;
  }

  @override
  License licenseOfType(LicenseType type) {
    throw 'tried to look up a dual-license license by type ("$type")';
  }

  @override
  License licenseWithName(String name) {
    throw 'tried to look up a dual-license license by name ("$name")';
  }

  @override
  License get defaultLicense => _licenses[0];

  @override
  Iterable<License> get licenses => _licenses;
}


// DIRECTORIES

class RepositoryDirectory extends RepositoryEntry implements LicenseSource {
  RepositoryDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io) {
    crawl();
  }

  @override
  fs.Directory get io => super.io;

  final List<RepositoryDirectory> _subdirectories = <RepositoryDirectory>[];
  final List<RepositoryLicensedFile> _files = <RepositoryLicensedFile>[];
  final List<RepositoryLicenseFile> _licenses = <RepositoryLicenseFile>[];

  final Map<String, RepositoryEntry> _childrenByName = <String, RepositoryEntry>{};

  // the bit at the beginning excludes files like "license.py".
  static final RegExp _licenseNamePattern = new RegExp(r'^(?!.*\.py$)(?!.*(?:no|update)-copyright)(?!.*mh-bsd-gcc).*\b_*(?:license(?!\.html)|copying|copyright|notice|l?gpl|bsd|mpl?|ftl\.txt)_*\b', caseSensitive: false);

  void crawl() {
    for (fs.IoNode entry in io.walk) {
      if (shouldRecurse(entry)) {
        assert(!_childrenByName.containsKey(entry.name));
        if (entry is fs.Directory) {
          RepositoryDirectory child = createSubdirectory(entry);
          _subdirectories.add(child);
          _childrenByName[child.name] = child;
        } else if (entry is fs.File) {
          try {
            RepositoryFile child = createFile(entry);
            assert(child != null);
            if (child is RepositoryLicensedFile) {
              _files.add(child);
            } else {
              assert(child is RepositoryLicenseFile);
              _licenses.add(child);
            }
            _childrenByName[child.name] = child;
          } catch (e) {
            system.stderr.writeln('failed to handle $entry: $e');
            rethrow;
          }
        } else {
          assert(entry is fs.Link);
        }
      }
    }
  }

  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != '.git' &&
           entry.name != '.github' &&
           entry.name != '.gitignore' &&
           entry.name != 'test' &&
           entry.name != 'test.disabled' &&
           entry.name != 'test_support' &&
           entry.name != 'tests' &&
           entry.name != 'javatests' &&
           entry.name != 'testing';
  }

  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'third_party')
      return new RepositoryGenericThirdPartyDirectory(this, entry);
    return new RepositoryDirectory(this, entry);
  }

  RepositoryFile createFile(fs.IoNode entry) {
    if (entry is fs.TextFile) {
      if (RepositoryApache4DNoticeFile.consider(entry)) {
        return new RepositoryApache4DNoticeFile(this, entry);
      } else {
        RepositoryFile result;
        if (entry.name == 'NOTICE')
          result = RepositoryLicenseRedirectFile.maybeCreateFrom(this, entry);
        if (result != null) {
          return result;
        } else if (entry.name.contains(_licenseNamePattern)) {
          return new RepositoryGeneralSingleLicenseFile(this, entry);
        } else if (entry.name == 'README.ijg') {
          return new RepositoryReadmeIjgFile(this, entry);
        } else {
          return new RepositorySourceFile(this, entry);
        }
      }
    } else if (entry.name == 'NOTICE.txt') {
      return new RepositoryMultiLicenseNoticesForFilesFile(this, entry);
    } else {
      return new RepositoryBinaryFile(this, entry);
    }
  }

  int get count => _files.length + _subdirectories.fold(0, (int count, RepositoryDirectory child) => count + child.count);

  @override
  List<License> nearestLicensesFor(String name) {
    if (_licenses.isEmpty) {
      if (_canGoUp(null))
        return parent.nearestLicensesFor('${io.name}/$name');
      return null;
    }
    if (_licenses.length == 1)
      return _licenses.single.licensesFor(name);
    List<License> licenses = _licenses.expand/*License*/((RepositoryLicenseFile license) sync* {
      List<License> licenses = license.licensesFor(name);
      if (licenses != null)
        yield* licenses;
    }).toList();
    if (licenses.isEmpty)
      return null;
    if (licenses.length > 1) {
      //print('unexpectedly found multiple matching licenses for: $name');
      return licenses; // TODO(ianh): disambiguate them, in case we have e.g. a dual GPL/BSD situation
    }
    return licenses;
  }

  @override
  License nearestLicenseOfType(LicenseType type) {
    List<License> licenses = _licenses.expand/*License*/((RepositoryLicenseFile license) sync* {
      License result = license.licenseOfType(type);
      if (result != null)
        yield result;
    }).toList();
    if (licenses.isEmpty) {
      if (_canGoUp(null))
        return parent.nearestLicenseOfType(type);
      return null;
    }
    if (licenses.length > 1) {
      print('unexpectedly found multiple matching licenses in $name of type $type');
      return null;
    }
    return licenses.single;
  }

  @override
  License nearestLicenseWithName(String name, { String authors }) {
    License result = _nearestAncestorLicenseWithName(name, authors: authors);
    if (result == null) {
      for (RepositoryDirectory directory in _subdirectories) {
        result = directory._localLicenseWithName(name, authors: authors);
        if (result != null)
          break;
      }
    }
    result ??= _fullWalkUpForLicenseWithName(name, authors: authors);
    result ??= _fullWalkUpForLicenseWithName(name, authors: authors, ignoreCase: true);
    if (authors != null && result == null) {
      // if (result == null)
      //   print('could not find $name for authors "$authors", now looking for any $name in $this');
      result = nearestLicenseWithName(name);
      // if (result == null)
      //   print('completely failed to find $name for authors "$authors"');
      // else
      //   print('ended up finding a $name for "${result.authors}" instead');
    }
    return result;
  }

  bool _canGoUp(String authors) {
    return parent != null && (authors != null || isLicenseRootException || (!isLicenseRoot && !parent.subdirectoriesAreLicenseRoots));
  }

  License _nearestAncestorLicenseWithName(String name, { String authors }) {
    License result = _localLicenseWithName(name, authors: authors);
    if (result != null)
      return result;
    if (_canGoUp(authors))
      return parent._nearestAncestorLicenseWithName(name, authors: authors);
    return null;
  }

  License _fullWalkUpForLicenseWithName(String name, { String authors, bool ignoreCase: false }) {
    return _canGoUp(authors)
            ? parent._fullWalkUpForLicenseWithName(name, authors: authors, ignoreCase: ignoreCase)
            : _fullWalkDownForLicenseWithName(name, authors: authors, ignoreCase: ignoreCase);
  }

  License _fullWalkDownForLicenseWithName(String name, { String authors, bool ignoreCase: false }) {
    License result = _localLicenseWithName(name, authors: authors, ignoreCase: ignoreCase);
    if (result == null) {
      for (RepositoryDirectory directory in _subdirectories) {
        result = directory._fullWalkDownForLicenseWithName(name, authors: authors, ignoreCase: ignoreCase);
        if (result != null)
          break;
      }
    }
    return result;
  }

  /// Unless isLicenseRootException is true, we should not walk up the tree from
  /// here looking for licenses.
  bool get isLicenseRoot => parent == null;

  /// Unless isLicenseRootException is true on a child, the child should not
  /// walk up the tree to here looking for licenses.
  bool get subdirectoriesAreLicenseRoots => false;

  @override
  String get libraryName {
    if (isLicenseRoot)
      return name;
    assert(parent != null);
    if (parent.subdirectoriesAreLicenseRoots)
      return name;
    return parent.libraryName;
  }

  /// Overrides isLicenseRoot and parent.subdirectoriesAreLicenseRoots for cases
  /// where a directory contains license roots instead of being one. This
  /// allows, for example, the expat third_party directory to contain a
  /// subdirectory with expat while itself containing a BUILD file that points
  /// to the LICENSE in the root of the repo.
  bool get isLicenseRootException => false;

  License _localLicenseWithName(String name, { String authors, bool ignoreCase: false }) {
    Map<String, RepositoryEntry> map;
    if (ignoreCase) {
      // we get here if we're trying a last-ditch effort at finding a file.
      // so this should happen only rarely.
      map = new HashMap<String, RepositoryEntry>(
        equals: (String n1, String n2) => n1.toLowerCase() == n2.toLowerCase(),
        hashCode: (String n) => n.toLowerCase().hashCode
      )
        ..addAll(_childrenByName);
    } else {
      map = _childrenByName;
    }
    final RepositoryEntry entry = map[name];
    License license;
    if (entry is RepositoryLicensedFile) {
      license = entry.licenses.single;
    } else if (entry is RepositoryLicenseFile) {
      license = entry.defaultLicense;
    } else if (entry != null) {
      if (authors == null)
        throw 'found "$name" in $this but it was a ${entry.runtimeType}';
    }
    if (license != null && authors != null) {
      if (license.authors?.toLowerCase() != authors.toLowerCase())
        license = null;
    }
    return license;
  }

  RepositoryEntry getChildByName(String name) {
    return _childrenByName[name];
  }

  Set<License> getLicenses(Progress progress) {
    Set<License> result = new Set<License>();
    _subdirectories.shuffle();
    for (RepositoryDirectory directory in _subdirectories/*.reversed*/)
      result.addAll(directory.getLicenses(progress));
    for (RepositoryLicensedFile file in _files) {
      if (file.isIncludedInBuildProducts) {
        try {
          progress.label = '$file';
          List<License> licenses = file.licenses;
          assert(licenses != null && licenses.isNotEmpty);
          result.addAll(licenses);
          progress.advance(true);
        } catch (e, stack) {
          system.stderr.writeln('error searching for copyright in: ${file.io}\n$e');
          if (e is! String)
            system.stderr.writeln(stack);
          system.stderr.writeln('\n');
          progress.advance(false);
        }
      }
    }
    for (RepositoryLicenseFile file in _licenses)
      result.addAll(file.licenses);
    return result;
  }

  int get fileCount {
    int result = 0;
    for (RepositoryLicensedFile file in _files) {
      if (file.isIncludedInBuildProducts)
        result += 1;
    }
    for (RepositoryDirectory directory in _subdirectories)
      result += directory.fileCount;
    return result;
  }
}

class RepositoryGenericThirdPartyDirectory extends RepositoryDirectory {
  RepositoryGenericThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool get subdirectoriesAreLicenseRoots => true;
}

class RepositoryReachOutFile extends RepositoryLicensedFile {
  RepositoryReachOutFile(RepositoryDirectory parent, fs.File io, this.offset) : super(parent, io);

  @override
  fs.File get io => super.io;

  final int offset;

  @override
  List<License> get licenses {
    RepositoryDirectory directory = parent;
    int index = offset;
    while (index > 1) {
      if (directory == null)
        break;
      directory = directory.parent;
      index -= 1;
    }
    return directory?.nearestLicensesFor(name);
  }
}

class RepositoryReachOutDirectory extends RepositoryDirectory {
  RepositoryReachOutDirectory(RepositoryDirectory parent, fs.Directory io, this.reachOutFilenames, this.offset) : super(parent, io);

  final Set<String> reachOutFilenames;
  final int offset;

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (reachOutFilenames.contains(entry.name))
      return new RepositoryReachOutFile(this, entry, offset);
    return super.createFile(entry);
  }
}

class RepositoryExcludeSubpathDirectory extends RepositoryDirectory {
  RepositoryExcludeSubpathDirectory(RepositoryDirectory parent, fs.Directory io, this.paths, [ this.index = 0 ]) : super(parent, io);

  final List<String> paths;
  final int index;

  @override
  bool shouldRecurse(fs.IoNode entry) {
    if (index == paths.length - 1 && entry.name == paths.last)
      return false;
    return super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == paths[index] && (index < paths.length - 1))
      return new RepositoryExcludeSubpathDirectory(this, entry, paths, index + 1);
    return super.createSubdirectory(entry);
  }
}


// WHAT TO CRAWL AND WHAT NOT TO CRAWL

class RepositoryAndroidSdkPlatformsWithJarDirectory extends RepositoryDirectory {
  RepositoryAndroidSdkPlatformsWithJarDirectory(RepositoryDirectory parent, fs.Directory io)
    : _jarLicense = <License>[new License.fromUrl('http://www.apache.org/licenses/LICENSE-2.0', origin: 'implicit android.jar license')],
      super(parent, io);

  final List<License> _jarLicense;

  @override
  List<License> nearestLicensesFor(String name) => _jarLicense;

  License nearestLicenseOfType(LicenseType type) {
    if (_jarLicense.single.type == type)
      return _jarLicense.single;
    return null;
  }

  License nearestLicenseWithName(String name, { String authors }) {
    return null;
  }

  @override
  bool shouldRecurse(fs.IoNode entry) {
    // we only use android.jar from the SDK, everything else we ignore
    return entry.name == 'android.jar';
  }
}

class RepositoryAndroidSdkPlatformsDirectory extends RepositoryDirectory {
  RepositoryAndroidSdkPlatformsDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'android-22') // chinmay says we only use 22 for the SDK
      return new RepositoryAndroidSdkPlatformsWithJarDirectory(this, entry);
    throw 'unknown Android SDK version: ${entry.name}';
  }
}

class RepositoryAndroidSdkDirectory extends RepositoryDirectory {
  RepositoryAndroidSdkDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    // We don't link with any of the Android SDK tools, Google-specific
    // packages, system images, samples, etc, when building the engine. We do
    // use some (especially those in build-tools/), but it is our understanding
    // that nothing from those files actually ends up in our final build output,
    // and therefore we don't worry about their licenses.
    return entry.name != 'add-ons'
        && entry.name != 'build-tools'
        && entry.name != 'extras'
        && entry.name != 'platform-tools'
        && entry.name != 'samples'
        && entry.name != 'system-images'
        && entry.name != 'tools'
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'platforms')
      return new RepositoryAndroidSdkPlatformsDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryAndroidNdkPlatformsDirectory extends RepositoryDirectory {
  RepositoryAndroidNdkPlatformsDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    if (entry.name == 'android-9' ||
        entry.name == 'android-12' ||
        entry.name == 'android-13' ||
        entry.name == 'android-14' ||
        entry.name == 'android-15' ||
        entry.name == 'android-17' ||
        entry.name == 'android-18' ||
        entry.name == 'android-19' ||
        entry.name == 'android-21' ||
        entry.name == 'android-23' ||
        entry.name == 'android-24')
      return false;
    if (entry.name == 'android-16' || // chinmay says we use this for armv7
        entry.name == 'android-22') // chinmay says we use this for everything else
      return true;
    throw 'unknown Android NDK version: ${entry.name}';
  }
}

class RepositoryAndroidNdkSourcesAndroidSupportDirectory extends RepositoryDirectory {
  RepositoryAndroidNdkSourcesAndroidSupportDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'NOTICE' && entry is fs.TextFile) {
      return new RepositoryGeneralSingleLicenseFile.fromLicense(
        this,
        entry,
        new License.unique(
          entry.readString(),
          LicenseType.unknown,
          origin: entry.fullName,
          yesWeKnowWhatItLooksLikeButItIsNot: true, // lawyer said to include this file verbatim
        )
      );
    }
    return super.createFile(entry);
  }

}

class RepositoryAndroidNdkSourcesAndroidDirectory extends RepositoryDirectory {
  RepositoryAndroidNdkSourcesAndroidDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'libthread_db' // README in that directory says we aren't using this
        && entry.name != 'crazy_linker' // build-time only (not that we use it anyway)
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'support')
      return new RepositoryAndroidNdkSourcesAndroidSupportDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryAndroidNdkSourcesCxxStlSubsubdirectory extends RepositoryDirectory {
  RepositoryAndroidNdkSourcesCxxStlSubsubdirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE.TXT')
      return new RepositoryCxxStlDualLicenseFile(this, entry);
    return super.createFile(entry);
  }
}

class RepositoryAndroidNdkSourcesCxxStlSubdirectory extends RepositoryDirectory {
  RepositoryAndroidNdkSourcesCxxStlSubdirectory(RepositoryDirectory parent, fs.Directory io, this.subdirectoryName) : super(parent, io);

  final String subdirectoryName;

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == subdirectoryName)
      return new RepositoryAndroidNdkSourcesCxxStlSubsubdirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryAndroidNdkSourcesCxxStlDirectory extends RepositoryDirectory {
  RepositoryAndroidNdkSourcesCxxStlDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool get subdirectoriesAreLicenseRoots => true;

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'gabi++' // abarth says jamesr says we don't use these two
        && entry.name != 'stlport'
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'llvm-libc++abi')
      return new RepositoryAndroidNdkSourcesCxxStlSubdirectory(this, entry, 'libcxxabi');
    if (entry.name == 'llvm-libc++')
      return new RepositoryAndroidNdkSourcesCxxStlSubdirectory(this, entry, 'libcxx');
    return super.createSubdirectory(entry);
  }
}

class RepositoryAndroidNdkSourcesThirdPartyDirectory extends RepositoryGenericThirdPartyDirectory {
  RepositoryAndroidNdkSourcesThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    if (entry.name == 'googletest')
      return false; // testing infrastructure, not shipped with flutter engine
    if (entry.name == 'shaderc')
      return false; // abarth says we don't use any shader stuff
    if (entry.name == 'vulkan')
      return false; // abath says we do use vulkan so might use this
    throw 'unexpected Android NDK third-party package: ${entry.name}';
  }
}

class RepositoryAndroidNdkSourcesDirectory extends RepositoryDirectory {
  RepositoryAndroidNdkSourcesDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'android')
      return new RepositoryAndroidNdkSourcesAndroidDirectory(this, entry);
    if (entry.name == 'cxx-stl')
      return new RepositoryAndroidNdkSourcesCxxStlDirectory(this, entry);
    if (entry.name == 'third_party')
      return new RepositoryAndroidNdkSourcesThirdPartyDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}


class RepositoryAndroidNdkDirectory extends RepositoryDirectory {
  RepositoryAndroidNdkDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    // we don't link with or use any of the Android NDK samples
    return entry.name != 'build'
        && entry.name != 'docs'
        && entry.name != 'prebuilt' // only used by engine debug builds, which we don't ship
        && entry.name != 'samples'
        && entry.name != 'tests'
        && entry.name != 'toolchains' // only used at build time, doesn't seem to contain anything that gets shipped with the build output
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'platforms')
      return new RepositoryAndroidNdkPlatformsDirectory(this, entry);
    if (entry.name == 'sources')
      return new RepositoryAndroidNdkSourcesDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryAndroidToolsDirectory extends RepositoryDirectory {
  RepositoryAndroidToolsDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool get subdirectoriesAreLicenseRoots => true;

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'VERSION_LINUX_SDK'
        && entry.name != 'VERSION_LINUX_NDK'
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'sdk')
      return new RepositoryAndroidSdkDirectory(this, entry);
    if (entry.name == 'ndk')
      return new RepositoryAndroidNdkDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryAndroidPlatformDirectory extends RepositoryDirectory {
  RepositoryAndroidPlatformDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    // we don't link with or use any of the Android NDK samples
    return entry.name != 'webview' // not used at all
        && entry.name != 'development' // not linked in
        && super.shouldRecurse(entry);
  }
}

class RepositoryExpatDirectory extends RepositoryDirectory {
  RepositoryExpatDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool get isLicenseRootException => true;

  @override
  bool get subdirectoriesAreLicenseRoots => true;
}

class RepositoryFreetypeDocsDirectory extends RepositoryDirectory {
  RepositoryFreetypeDocsDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE.TXT')
      return new RepositoryFreetypeLicenseFile(this, entry);
    return super.createFile(entry);
  }

  @override
  int get fileCount => 0;

  @override
  Set<License> getLicenses(Progress progress) {
    // We don't ship anything in this directory so don't bother looking for licenses there.
    // However, there are licenses in this directory referenced from elsewhere, so we do
    // want to crawl it and expose them.
    return new Set<License>();
  }
}

class RepositoryFreetypeSrcGZipDirectory extends RepositoryDirectory {
  RepositoryFreetypeSrcGZipDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  // advice was to make this directory's inffixed.h file (which has no license)
  // use the license in zlib.h.

  @override
  List<License> nearestLicensesFor(String name) {
    License zlib = nearestLicenseWithName('zlib.h');
    assert(zlib != null);
    if (zlib != null)
      return <License>[zlib];
    return super.nearestLicensesFor(name);
  }

  License nearestLicenseOfType(LicenseType type) {
    if (type == LicenseType.zlib) {
      License result = nearestLicenseWithName('zlib.h');
      assert(result != null);
      return result;
    }
    return null;
  }
}

class RepositoryFreetypeSrcDirectory extends RepositoryDirectory {
  RepositoryFreetypeSrcDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'gzip')
      return new RepositoryFreetypeSrcGZipDirectory(this, entry);
    return super.createSubdirectory(entry);
  }

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'tools'
        && super.shouldRecurse(entry);
  }
}

class RepositoryFreetypeDirectory extends RepositoryDirectory {
  RepositoryFreetypeDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  List<License> nearestLicensesFor(String name) {
    List<License> result = super.nearestLicensesFor(name);
    if (result == null) {
      License FTL = nearestLicenseWithName('LICENSE.TXT');
      assert(FTL != null);
      if (FTL != null)
        return <License>[FTL];
    }
    return result;
  }

  License nearestLicenseOfType(LicenseType type) {
    if (type == LicenseType.freetype) {
      License result = nearestLicenseWithName('FTL.TXT');
      assert(result != null);
      return result;
    }
    return null;
  }

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'builds' // build files
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'src')
      return new RepositoryFreetypeSrcDirectory(this, entry);
    if (entry.name == 'docs')
      return new RepositoryFreetypeDocsDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryIcuDirectory extends RepositoryDirectory {
  RepositoryIcuDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'license.html' // redundant with LICENSE file
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE')
      return new RepositoryIcuLicenseFile(this, entry);
    return super.createFile(entry);
  }
}

class RepositoryJSR305Directory extends RepositoryDirectory {
  RepositoryJSR305Directory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'src')
      return new RepositoryJSR305SrcDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryJSR305SrcDirectory extends RepositoryDirectory {
  RepositoryJSR305SrcDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'javadoc'
        && entry.name != 'sampleUses'
        && super.shouldRecurse(entry);
  }
}

class RepositoryLibJpegDirectory extends RepositoryDirectory {
  RepositoryLibJpegDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'README')
      return new RepositoryReadmeIjgFile(this, entry);
    if (entry.name == 'LICENSE')
      return new RepositoryLicenseFileWithLeader(this, entry, new RegExp(r'^\(Copied from the README\.\)\n+-+\n+'));
    return super.createFile(entry);
  }
}

class RepositoryLibJpegTurboDirectory extends RepositoryDirectory {
  RepositoryLibJpegTurboDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE.md')
      return new RepositoryLibJpegTurboLicense(this, entry);
    return super.createFile(entry);
  }

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'release' // contains nothing that ends up in the binary executable
        && entry.name != 'doc' // contains nothing that ends up in the binary executable
        && entry.name != 'testimages' // test assets
        && super.shouldRecurse(entry);
  }
}

class RepositoryLibPngDirectory extends RepositoryDirectory {
  RepositoryLibPngDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE' || entry.name == 'png.h')
      return new RepositoryLibPngLicenseFile(this, entry);
    return super.createFile(entry);
  }
}

class RepositoryOkHttpDirectory extends RepositoryDirectory {
  RepositoryOkHttpDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE')
      return new RepositoryOkHttpLicenseFile(this, entry);
    return super.createFile(entry);
  }
}

class RepositorySkiaLibWebPDirectory extends RepositoryDirectory {
  RepositorySkiaLibWebPDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'webp')
      return new RepositoryReachOutDirectory(this, entry, new Set<String>.from(const <String>['config.h']), 3);
    return super.createSubdirectory(entry);
  }
}

class RepositorySkiaLibSdlDirectory extends RepositoryDirectory {
  RepositorySkiaLibSdlDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool get isLicenseRootException => true;
}

class RepositorySkiaThirdPartyDirectory extends RepositoryGenericThirdPartyDirectory {
  RepositorySkiaThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'giflib' // contains nothing that ends up in the binary executable
        && entry.name != 'freetype' // we use our own version
        && entry.name != 'lua' // not linked in
        && entry.name != 'yasm' // build tool (assembler)
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'ktx')
      return new RepositoryReachOutDirectory(this, entry, new Set<String>.from(const <String>['ktx.h', 'ktx.cpp']), 2);
    if (entry.name == 'libmicrohttpd')
      return new RepositoryReachOutDirectory(this, entry, new Set<String>.from(const <String>['MHD_config.h']), 2);
    if (entry.name == 'libpng')
      return new RepositoryLibPngDirectory(this, entry);
    if (entry.name == 'libwebp')
      return new RepositorySkiaLibWebPDirectory(this, entry);
    if (entry.name == 'libsdl')
      return new RepositorySkiaLibSdlDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositorySkiaDirectory extends RepositoryDirectory {
  RepositorySkiaDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'platform_tools' // contains nothing that ends up in the binary executable
        && entry.name != 'tools' // contains nothing that ends up in the binary executable
        && entry.name != 'resources' // contains nothing that ends up in the binary executable
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'third_party')
      return new RepositorySkiaThirdPartyDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryXdgMimeDirectory extends RepositoryDirectory {
  RepositoryXdgMimeDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE')
      return new RepositoryXdgMimeLicenseFile(this, entry);
    return super.createFile(entry);
  }
}

class RepositoryVulkanDirectory extends RepositoryDirectory {
  RepositoryVulkanDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'doc' // documentation
        && entry.name != 'out' // documentation
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'src')
      return new RepositoryExcludeSubpathDirectory(this, entry, const <String>['spec']);
    return super.createSubdirectory(entry);
  }
}

class RepositoryRootThirdPartyDirectory extends RepositoryGenericThirdPartyDirectory {
  RepositoryRootThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'appurify-python' // only used by tests
        && entry.name != 'dart-sdk' // redundant with //engine/dart; https://github.com/flutter/flutter/issues/2618
        && entry.name != 'firebase' // only used by bots; https://github.com/flutter/flutter/issues/3722
        && entry.name != 'jinja2' // build-time code generation
        && entry.name != 'junit' // only mentioned in build files, not used
        && entry.name != 'libxml' // dependency of the testing system that we don't actually use
        && entry.name != 'llvm-build' // only used by build
        && entry.name != 'markupsafe' // build-time only
        && entry.name != 'mockito' // only used by tests
        && entry.name != 'pymock' // presumably only used by tests
        && entry.name != 'robolectric' // testing framework for android
        && entry.name != 'yasm' // build-time dependency only
        && entry.name != 'binutils' // build-time dependency only
        && entry.name != 'instrumented_libraries' // unused according to chinmay
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'android_tools')
      return new RepositoryAndroidToolsDirectory(this, entry);
    if (entry.name == 'android_platform')
      return new RepositoryAndroidPlatformDirectory(this, entry);
    if (entry.name == 'boringssl')
      return new RepositoryBoringSSLDirectory(this, entry);
    if (entry.name == 'expat')
      return new RepositoryExpatDirectory(this, entry);
    if (entry.name == 'freetype-android')
      throw 'detected unexpected resurgence of freetype-android';
    if (entry.name == 'freetype2')
      return new RepositoryFreetypeDirectory(this, entry);
    if (entry.name == 'icu')
      return new RepositoryIcuDirectory(this, entry);
    if (entry.name == 'jsr-305')
      return new RepositoryJSR305Directory(this, entry);
    if (entry.name == 'libjpeg')
      return new RepositoryLibJpegDirectory(this, entry);
    if (entry.name == 'libjpeg_turbo' || entry.name == 'libjpeg-turbo')
      return new RepositoryLibJpegTurboDirectory(this, entry);
    if (entry.name == 'libpng')
      return new RepositoryLibPngDirectory(this, entry);
    if (entry.name == 'okhttp')
      return new RepositoryOkHttpDirectory(this, entry);
    if (entry.name == 'skia')
      return new RepositorySkiaDirectory(this, entry);
    if (entry.name == 'vulkan')
      return new RepositoryVulkanDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryBaseThirdPartyDirectory extends RepositoryGenericThirdPartyDirectory {
  RepositoryBaseThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'dynamic-annotations' // only used by a random test
        && entry.name != 'valgrind' // unopt engine builds only
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'xdg_mime')
      return new RepositoryXdgMimeDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryBaseDirectory extends RepositoryDirectory {
  RepositoryBaseDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool get isLicenseRoot => true;

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'third_party')
      return new RepositoryBaseThirdPartyDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryBoringSSLThirdPartyDirectory extends RepositoryDirectory {
  RepositoryBoringSSLThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'android-cmake' // build-time only
        && super.shouldRecurse(entry);
  }
}

class RepositoryBoringSSLSourceDirectory extends RepositoryDirectory {
  RepositoryBoringSSLSourceDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  String get libraryName => 'boringssl';

  @override
  bool get isLicenseRoot => true;

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'fuzz' // testing tools, not shipped
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'third_party')
      return new RepositoryBoringSSLThirdPartyDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryBoringSSLDirectory extends RepositoryDirectory {
  RepositoryBoringSSLDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'README')
      return new RepositoryBlankLicenseFile(this, entry, 'This repository contains the files generated by boringssl for its build.');
    return super.createFile(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'src')
      return new RepositoryBoringSSLSourceDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryDartRuntimeThirdPartyDirectory extends RepositoryGenericThirdPartyDirectory {
  RepositoryDartRuntimeThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'd3' // Siva says "that is the charting library used by the binary size tool"
        && entry.name != 'binary_size' // not linked in either
        && super.shouldRecurse(entry);
  }
}

class RepositoryDartThirdPartyDirectory extends RepositoryGenericThirdPartyDirectory {
  RepositoryDartThirdPartyDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'drt_resources' // test materials
        && entry.name != 'firefox_jsshell' // testing tool for dart2js
        && entry.name != 'd8' // testing tool for dart2js
        && entry.name != 'pkg'
        && entry.name != 'pkg_tested'
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'boringssl')
      return new RepositoryBoringSSLDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryDartRuntimeDirectory extends RepositoryDirectory {
  RepositoryDartRuntimeDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'third_party')
      return new RepositoryDartRuntimeThirdPartyDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryDartDirectory extends RepositoryDirectory {
  RepositoryDartDirectory(RepositoryDirectory parent, fs.Directory io) : super(parent, io);

  @override
  bool get isLicenseRoot => true;

  @override
  RepositoryFile createFile(fs.IoNode entry) {
    if (entry.name == 'LICENSE')
      return new RepositoryDartLicenseFile(this, entry);
    return super.createFile(entry);
  }

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'pkg' // packages that don't become part of the binary (e.g. the analyzer)
        && entry.name != 'tests' // only used by tests, obviously
        && entry.name != 'docs' // not shipped in binary
        && entry.name != 'tools' // not shipped in binary
        && entry.name != 'samples-dev' // not shipped in binary
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'third_party')
      return new RepositoryDartThirdPartyDirectory(this, entry);
    if (entry.name == 'runtime')
      return new RepositoryDartRuntimeDirectory(this, entry);
    return super.createSubdirectory(entry);
  }
}

class RepositoryRoot extends RepositoryDirectory {
  RepositoryRoot(fs.Directory io) : super(null, io);

  @override
  String get libraryName => 'engine';

  @override
  bool get isLicenseRoot => true;

  @override
  bool shouldRecurse(fs.IoNode entry) {
    return entry.name != 'testing' // only used by tests
        && entry.name != 'build' // only used by build
        && entry.name != 'buildtools' // only used by build
        && entry.name != 'tools' // not distributed in binary
        && entry.name != 'out' // output of build
        && super.shouldRecurse(entry);
  }

  @override
  RepositoryDirectory createSubdirectory(fs.Directory entry) {
    if (entry.name == 'third_party')
      return new RepositoryRootThirdPartyDirectory(this, entry);
    if (entry.name == 'base')
      return new RepositoryBaseDirectory(this, entry);
    if (entry.name == 'dart')
      return new RepositoryDartDirectory(this, entry);
    // if (entry.name == 'mojo')
    //   return new RepositoryMojoDirectory(this, entry);
    if (entry.name == 'flutter')
      return new RepositoryExcludeSubpathDirectory(this, entry, const <String>['sky', 'packages', 'sky_engine', 'LICENSE']); // that's the output of this script!
    return super.createSubdirectory(entry);
  }
}


class Progress {
  Progress(this.max);
  final int max;
  int get withLicense => _withLicense;
  int _withLicense = 0;
  int get withoutLicense => _withoutLicense;
  int _withoutLicense = 0;
  String get label => _label;
  String _label = '';
  set label(String value) {
    _label = value;
    update();
  }
  void advance(bool success) {
    if (success)
      _withLicense += 1;
    else
      _withoutLicense += 1;
    update();
  }
  void update() {
    system.stderr.write('$this\r');
  }
  bool get hadErrors => _withoutLicense > 0;
  @override
  String toString() {
    int percent = (100.0 * (_withLicense + _withoutLicense) / max).round();
    return '${(_withLicense + _withoutLicense).toString().padLeft(10)} of $max ${'█' * (percent ~/ 10)}${'░' * (10 - (percent ~/ 10))} $percent% ($_withoutLicense missing licenses)  $label    ';
  }
}


// MAIN

void main(List<String> arguments) {
  if (arguments.length != 1) {
    print('Usage: dart lib/main.dart path/to/engine/root/src');
    system.exit(1);
  }

  try {
    system.stderr.writeln('Preparing data structures...');
    final RepositoryDirectory root = new RepositoryRoot(new fs.FileSystemDirectory.fromPath(arguments.single));
    system.stderr.writeln('Collecting licenses...');
    Progress progress = new Progress(root.fileCount);
    List<License> licenses = new Set<License>.from(root.getLicenses(progress).toList()).toList();
    progress.label = 'Dumping results...';
    bool done = false;
    List<License> usedLicenses = licenses.where((License license) => license.isUsed).toList();
    assert(() {
      print('UNUSED LICENSES:\n');
      print(licenses.where((License license) => !license.isUsed).join('\n\n'));
      print('~' * 80);
      print('USED LICENSES:\n');
      List<String> output = usedLicenses.map((License license) => license.toString()).toList();
      output.sort();
      print(output.join('\n\n'));
      done = true;
      return true;
    });
    if (!done) {
      if (progress.hadErrors)
        throw 'Had failures while collecting licenses.';
      List<String> output = usedLicenses
        .map((License license) => license.toStringFormal())
        .where((String text) => text != null)
        .toList();
      output.sort();
      print(output.join('\n${"-" * 80}\n'));
    }
    assert(() {
      print('Total license count: ${licenses.length}');
      progress.label = 'Done.';
      print('$progress');
      return true;
    });
  } catch (e, stack) {
    system.stderr.writeln('failure: $e\n$stack');
    system.stderr.writeln('aborted.');
    system.exit(1);
  }
}

// Sanity checks:
//
// The following substrings shouldn't be in the output:
//   Version: MPL 1.1/GPL 2.0/LGPL 2.1
//   The contents of this file are subject to the Mozilla Public License Version
//   You should have received a copy of the GNU
//   BoringSSL is a fork of OpenSSL
//   Contents of this folder are ported from
//   https://github.com/w3c/web-platform-tests/tree/master/selectors-api
//   It is based on commit
//   The original code is covered by the dual-licensing approach described in:
//   http://www.w3.org/Consortium/Legal/2008/04-testsuite-copyright.html
//   must choose
