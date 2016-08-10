// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:archive/archive.dart' as a;

import 'cache.dart';

enum FileType {
  binary, // won't have its own license block
  text, // might have its own UTF-8 license block
  latin1Text, // might have its own Windows-1252 license block
  zip, // should be parsed as an archive and drilled into
  tar, // should be parsed as an archive and drilled into
  gz, // should be parsed as a single compressed file and exposed
  bzip2, // should be parsed as a single compressed file and exposed
}

typedef List<int> Reader();

class BytesOf extends Key { BytesOf(dynamic value) : super(value); }
class UTF8Of extends Key { UTF8Of(dynamic value) : super(value); }
class Latin1Of extends Key { Latin1Of(dynamic value) : super(value); }

bool matchesSignature(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length)
    return false;
  for (int index = 0; index < signature.length; index += 1) {
    if (signature[index] != -1 && bytes[index] != signature[index])
      return false;
  }
  return true;
}

const String kMultiLicenseFileHeader = 'Notices for files contained in';

bool isMultiLicenseNotice(Reader reader) {
  List<int> bytes = reader();
  return (ASCII.decode(bytes.take(kMultiLicenseFileHeader.length).toList(), allowInvalid: true) == kMultiLicenseFileHeader);
}

FileType identifyFile(String name, Reader reader) {
  if ((path.split(name).reversed.take(6).toList().reversed.join('/') == 'third_party/icu/source/extra/uconv/README') || // This specific ICU README isn't in UTF-8.
      (path.split(name).reversed.take(6).toList().reversed.join('/') == 'third_party/icu/source/samples/uresb/sr.txt') || // This specific sample contains non-UTF-8 data (unlike other sr.txt files).
      (path.split(name).reversed.take(4).toList().reversed.join('/') == 'freetype-android/src/builds/detect.mk') || // This specific sample contains non-UTF-8 data (unlike other .mk files).
      (path.split(name).reversed.take(5).toList().reversed.join('/') == 'third_party/freetype-android/src/docs/FTL.TXT')) // This file has a copyright symbol in Latin1 in it
    return FileType.latin1Text;
  if (path.split(name).reversed.take(6).toList().reversed.join('/') == 'dart/runtime/tests/vm/dart/bad_snapshot' || // Not any particular format
      path.split(name).reversed.take(8).toList().reversed.join('/') == 'third_party/android_tools/ndk/sources/cxx-stl/stlport/src/stlport.rc') // uses the word "copyright" but doesn't have a copyright header
    return FileType.binary;
  switch (path.basename(name)) {
    // Build files
    case 'DEPS': return FileType.text;
    case 'MANIFEST': return FileType.text;
    // Licenses
    case 'COPYING': return FileType.text;
    case 'LICENSE': return FileType.text;
    case 'NOTICE.txt': return isMultiLicenseNotice(reader) ? FileType.binary : FileType.text;
    case 'NOTICE': return FileType.text;
    // Documentation
    case 'Changes': return FileType.text;
    case 'change.log': return FileType.text;
    case 'ChangeLog': return FileType.text;
    case 'README': return FileType.text;
    case 'TODO': return FileType.text;
    case 'NEWS': return FileType.text;
    case 'README.chromium': return FileType.text;
    case 'README.flutter': return FileType.text;
    case 'README.tests': return FileType.text;
    case 'OWNERS': return FileType.text;
    case 'AUTHORS': return FileType.text;
    // Signatures (found in .jar files typically)
    case 'CERT.RSA': return FileType.binary;
    case 'ECLIPSE_.RSA': return FileType.binary;
    // Binary data files
    case 'tzdata': return FileType.binary;
    // Source files that don't use UTF-8
    case 'Messages_de_DE.properties': // has a few non-ASCII characters they forgot to escape (from gnu-libstdc++)
    case 'bool_set': // has latin1 in a person's name in a comment
    case 'mmx_blendtmp.h': // author name in comment contains latin1 (mesa)
    case 'calling_convention.txt': // contains a soft hyphen instead of a real hyphen for some reason (mesa)
    // Character encoding data files
    case 'danish-ISO-8859-1.txt':
    case 'eucJP.txt':
    case 'hangul-eucKR.txt':
    case 'hania-eucKR.txt':
    case 'ibm-37-test.txt':
    case 'iso8859-1.txt':
    case 'ISO-8859-2.txt':
    case 'ISO-8859-3.txt':
    case 'koi8r.txt':
      return FileType.latin1Text;
    // Giant data files
    case 'icudtl_dat.S':
    case 'icudtl.dat':
      return FileType.binary;
  }
  switch (path.extension(name)) {
    // C/C++ code
    case '.h': return FileType.text;
    case '.c': return FileType.text;
    case '.cc': return FileType.text;
    case '.cpp': return FileType.text;
    case '.inc': return FileType.text;
    // ObjectiveC code
    case '.m': return FileType.text;
    // Assembler
    case '.asm': return FileType.text;
    // Shell
    case '.sh': return FileType.text;
    case '.bat': return FileType.text;
    // Build files
    case '.in': return FileType.text;
    case '.ac': return FileType.text;
    case '.am': return FileType.text;
    case '.gn': return FileType.text;
    case '.gni': return FileType.text;
    case '.gyp': return FileType.text;
    case '.gypi': return FileType.text;
    // Java code
    case '.java': return FileType.text;
    case '.jar': return FileType.zip; // Java package
    case '.class': return FileType.binary; // compiled Java bytecode (usually found inside .jar archives)
    case '.dex': return FileType.binary; // Dalvik Executable (usually found inside .jar archives)
    // Dart code
    case '.dart': return FileType.text;
    // LLVM bitcode
    case '.bc': return FileType.binary;
    // Python code
    case '.py': return FileType.text;
    case '.pyc': return FileType.binary; // compiled Python bytecode
    // Machine code
    case '.so': return FileType.binary; // ELF shared object
    case '.xpt': return FileType.binary; // XPCOM Type Library
    // Documentation
    case '.md': return FileType.text;
    case '.txt': return FileType.text;
    case '.diff': return FileType.text;
    case '.html': return FileType.text;
    // Fonts
    case '.ttf': return FileType.binary; // TrueType Font
    case '.ttcf': // (mac)
    case '.ttc': return FileType.binary; // TrueType Collection (windows)
    case '.otf': return FileType.binary; // OpenType Font
    // Graphics formats
    case '.gif': return FileType.binary; // GIF
    case '.png': return FileType.binary; // PNG
    case '.tga': return FileType.binary; // Truevision TGA (TARGA)
    case '.dng': return FileType.binary; // Digial Negative (Adobe RAW format)
    case '.jpg':
    case '.jpeg': return FileType.binary; // JPEG
    case '.ico': return FileType.binary; // Windows icon format
    case '.bmp': return FileType.binary; // Windows bitmap format
    case '.wbmp': return FileType.binary; // Wireless bitmap format
    case '.webp': return FileType.binary; // WEBP
    case '.pdf': return FileType.binary; // PDF
    // Videos
    case '.ogg': return FileType.binary; // Ogg media
    case '.mp4': return FileType.binary; // MPEG media
    case '.ts': return FileType.binary; // MPEG2 transport stream
    // Other binary files
    case '.raw': return FileType.binary; // raw audio or graphical data
    case '.bin': return FileType.binary; // some sort of binary data
    case '.dat': return FileType.binary; // some sort of binary data
    case '.rsc': return FileType.binary; // some sort of resource data
    case '.arsc': return FileType.binary; // Android compiled resources
    case '.apk': return FileType.zip; // Android Package
    case '.crx': return FileType.binary; // Chrome extension
    case '.keystore': return FileType.binary;
    case '.icc': return FileType.binary;
    // Archives
    case '.zip': return FileType.zip; // ZIP
    case '.tar': return FileType.tar; // Tar
    case '.gz': return FileType.gz; // GZip
    case '.bzip2': return FileType.bzip2; // BZip2
    // Special cases
    case '.patch':
    case '.diff':
      // Don't try to read the copyright out of patch files, since there'll be fragments.
      return FileType.binary;
    case '.plist':
      // These commonly include the word "copyright" but in a way that isn't necessarily a copyright statement that applies to the file.
      // Since there's so few of them, and none have their own copyright statement, we just treat them as binary files.
      return FileType.binary;
  }
  List<int> bytes = reader();
  assert(bytes.length > 0);
  if (matchesSignature(bytes, <int>[0x1F, 0x8B]))
    return FileType.gz; // GZip archive
  if (matchesSignature(bytes, <int>[0x42, 0x5A]))
    return FileType.bzip2; // BZip2 archive
  if (matchesSignature(bytes, <int>[0x42, 0x43]))
    return FileType.binary; // LLVM Bitcode
  if (matchesSignature(bytes, <int>[0xAC, 0xED]))
    return FileType.binary; // Java serialized object
  if (matchesSignature(bytes, <int>[0x4D, 0x5A]))
    return FileType.binary; // MZ executable (DOS, Windows PEs, etc)
  if (matchesSignature(bytes, <int>[0xFF, 0xD8, 0xFF]))
    return FileType.binary; // JPEG
  if (matchesSignature(bytes, <int>[-1, -1, 0xda, 0x27])) // -1 is a wildcard
    return FileType.binary; // ICU data files (.brk, .dict, etc)
  if (matchesSignature(bytes, <int>[0x03, 0x00, 0x08, 0x00]))
    return FileType.binary; // Android Binary XML
  if (matchesSignature(bytes, <int>[0x25, 0x50, 0x44, 0x46]))
    return FileType.binary; // PDF
  if (matchesSignature(bytes, <int>[0x43, 0x72, 0x32, 0x34]))
    return FileType.binary; // Chrome extension
  if (matchesSignature(bytes, <int>[0x4F, 0x67, 0x67, 0x53]))
    return FileType.binary; // Ogg media
  if (matchesSignature(bytes, <int>[0x50, 0x4B, 0x03, 0x04]))
    return FileType.zip; // ZIP archive
  if (matchesSignature(bytes, <int>[0x7F, 0x45, 0x4C, 0x46]))
    return FileType.binary; // ELF
  if (matchesSignature(bytes, <int>[0xCA, 0xFE, 0xBA, 0xBE]))
    return FileType.binary; // compiled Java bytecode (usually found inside .jar archives)
  if (matchesSignature(bytes, <int>[0xCE, 0xFA, 0xED, 0xFE]))
    return FileType.binary; // Mach-O binary, 32 bit, reverse byte ordering scheme
  if (matchesSignature(bytes, <int>[0xCF, 0xFA, 0xED, 0xFE]))
    return FileType.binary; // Mach-O binary, 64 bit, reverse byte ordering scheme
  if (matchesSignature(bytes, <int>[0xFE, 0xED, 0xFA, 0xCE]))
    return FileType.binary; // Mach-O binary, 32 bit
  if (matchesSignature(bytes, <int>[0xFE, 0xED, 0xFA, 0xCF]))
    return FileType.binary; // Mach-O binary, 64 bit
  if (matchesSignature(bytes, <int>[0x75, 0x73, 0x74, 0x61, 0x72]))
    return FileType.bzip2; // Tar
  if (matchesSignature(bytes, <int>[0x47, 0x49, 0x46, 0x38, 0x37, 0x61]))
    return FileType.binary; // GIF87a
  if (matchesSignature(bytes, <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61]))
    return FileType.binary; // GIF89a
  if (matchesSignature(bytes, <int>[0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00]))
    return FileType.binary; // Dalvik Executable
  if (matchesSignature(bytes, <int>[0x21, 0x3C, 0x61, 0x72, 0x63, 0x68, 0x3E, 0x0A]))
    return FileType.binary; // Unix archiver (ar) // TODO(ianh): implement .ar parser
  if (matchesSignature(bytes, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0a]))
    return FileType.binary; // PNG
  if (matchesSignature(bytes, <int>[0x58, 0x50, 0x43, 0x4f, 0x4d, 0x0a, 0x54, 0x79, 0x70, 0x65, 0x4c, 0x69, 0x62, 0x0d, 0x0a, 0x1a]))
    return FileType.binary; // XPCOM Type Library
  return FileType.text;
}


// INTERFACE

// base class
abstract class IoNode {
  // Subclasses of IoNode are not mutually exclusive.
  // For example, a ZIP file is represented as a File that also implements Directory.
  String get name;
  String get fullName;

  @override
  String toString() => fullName;
}

// interface
abstract class File extends IoNode {
  List<int> readBytes();
}

// interface
abstract class TextFile extends File {
  String readString();
}

// mixin
abstract class UTF8TextFile extends TextFile {
  @override
  String readString() {
    try {
      return cache(new UTF8Of(this), () => UTF8.decode(readBytes()));
    } on FormatException {
      print(fullName);
      rethrow;
    }
  }
}

// mixin
abstract class Latin1TextFile extends TextFile {
  @override
  String readString() {
    return cache(new Latin1Of(this), () {
      final List<int> bytes = readBytes();
      if (bytes.any((int byte) => byte == 0x00))
        throw '$fullName contains a U+0000 NULL and is probably not actually encoded as Win1252';
      bool isUTF8 = false;
      try {
        cache(new UTF8Of(this), () => UTF8.decode(readBytes()));
        isUTF8 = true;
      } on FormatException {
      }
      if (isUTF8)
        throw '$fullName contains valid UTF-8 and is probably not actually encoded as Win1252';
      return LATIN1.decode(bytes);
    });
  }
}

// interface
abstract class Directory extends IoNode {
  Iterable<IoNode> get walk;
}

// interface
abstract class Link extends IoNode { }

// mixin
abstract class ZipFile extends File implements Directory {
  ArchiveDirectory _root;

  @override
  Iterable<IoNode> get walk {
    try {
      _root ??= ArchiveDirectory.parseArchive(new a.ZipDecoder().decodeBytes(readBytes()), fullName);
      return _root.walk;
    } catch (exception) {
      print('failed to parse archive:\n$fullName');
      rethrow;
    }
  }
}

// mixin
abstract class TarFile extends File implements Directory {
  ArchiveDirectory _root;

  @override
  Iterable<IoNode> get walk {
    try {
      _root ??= ArchiveDirectory.parseArchive(new a.TarDecoder().decodeBytes(readBytes()), fullName);
      return _root.walk;
    } catch (exception) {
      print('failed to parse archive:\n$fullName');
      rethrow;
    }
  }
}

// mixin
abstract class GZipFile extends File implements Directory {
  InMemoryFile _data;

  @override
  Iterable<IoNode> get walk sync* {
    try {
      String innerName = path.basenameWithoutExtension(fullName);
      _data ??= InMemoryFile.parse(fullName + '!' + innerName, new a.GZipDecoder().decodeBytes(readBytes()));
      if (_data != null)
        yield _data;
    } catch (exception) {
      print('failed to parse archive:\n$fullName');
      rethrow;
    }
  }
}

// mixin
abstract class BZip2File extends File implements Directory {
  InMemoryFile _data;

  @override
  Iterable<IoNode> get walk sync* {
    try {
      String innerName = path.basenameWithoutExtension(fullName);
      _data ??= InMemoryFile.parse(fullName + '!' + innerName, new a.BZip2Decoder().decodeBytes(readBytes()));
      if (_data != null)
        yield _data;
    } catch (exception) {
      print('failed to parse archive:\n$fullName');
      rethrow;
    }
  }
}


// FILESYSTEM IMPLEMENTATIoN

class FileSystemDirectory extends IoNode implements Directory {
  FileSystemDirectory(this._directory);

  factory FileSystemDirectory.fromPath(String name) {
    return new FileSystemDirectory(new io.Directory(name));
  }

  final io.Directory _directory;

  @override
  String get name => path.basename(_directory.path);

  @override
  String get fullName => _directory.path;

  List<int> _readBytes(io.File file) {
    return cache/*List<int>*/(new BytesOf(file), () => file.readAsBytesSync());
  }

  @override
  Iterable<IoNode> get walk sync* {
    for (io.FileSystemEntity entity in _directory.listSync()) {
      if (entity is io.Directory) {
        yield new FileSystemDirectory(entity);
      } else if (entity is io.Link) {
        yield new FileSystemLink(entity);
      } else {
        assert(entity is io.File);
        io.File fileEntity = entity;
        if (fileEntity.lengthSync() > 0) {
          switch (identifyFile(fileEntity.path, () => _readBytes(fileEntity))) {
            case FileType.binary: yield new FileSystemFile(fileEntity); break;
            case FileType.zip: yield new FileSystemZipFile(fileEntity); break;
            case FileType.tar: yield new FileSystemTarFile(fileEntity); break;
            case FileType.gz: yield new FileSystemGZipFile(fileEntity); break;
            case FileType.bzip2: yield new FileSystemBZip2File(fileEntity); break;
            case FileType.text: yield new FileSystemUTF8TextFile(fileEntity); break;
            case FileType.latin1Text: yield new FileSystemLatin1TextFile(fileEntity); break;
          }
        }
      }
    }
  }
}

class FileSystemLink extends IoNode implements Link {
  FileSystemLink(this._link);

  final io.Link _link;

  @override
  String get name => path.basename(_link.path);

  @override
  String get fullName => _link.path;
}

class FileSystemFile extends IoNode implements File {
  FileSystemFile(this._file);

  final io.File _file;

  @override
  String get name => path.basename(_file.path);

  @override
  String get fullName => _file.path;

  @override
  List<int> readBytes() {
    return cache(new BytesOf(_file), () => _file.readAsBytesSync());
  }
}

class FileSystemUTF8TextFile extends FileSystemFile with UTF8TextFile {
  FileSystemUTF8TextFile(io.File file) : super(file);
}

class FileSystemLatin1TextFile extends FileSystemFile with Latin1TextFile {
  FileSystemLatin1TextFile(io.File file) : super(file);
}

class FileSystemZipFile extends FileSystemFile with ZipFile {
  FileSystemZipFile(io.File file) : super(file);
}

class FileSystemTarFile extends FileSystemFile with TarFile {
  FileSystemTarFile(io.File file) : super(file);
}

class FileSystemGZipFile extends FileSystemFile with GZipFile {
  FileSystemGZipFile(io.File file) : super(file);
}

class FileSystemBZip2File extends FileSystemFile with BZip2File {
  FileSystemBZip2File(io.File file) : super(file);
}


// ARCHIVES

class ArchiveDirectory extends IoNode implements Directory {
  ArchiveDirectory(this.fullName, this.name);

  @override
  final String fullName;

  @override
  final String name;

  Map<String, ArchiveDirectory> _subdirectories = <String, ArchiveDirectory>{};
  List<ArchiveFile> _files = <ArchiveFile>[];

  void _add(a.ArchiveFile entry, List<String> remainingPath) {
    if (remainingPath.length > 1) {
      final String subdirectoryName = remainingPath.removeAt(0);
      _subdirectories.putIfAbsent(
        subdirectoryName,
        () => new ArchiveDirectory('$fullName/$subdirectoryName', subdirectoryName)
      )._add(entry, remainingPath);
    } else {
      if (entry.size > 0) {
        final String entryFullName = fullName + '/' + path.basename(entry.name);
        switch (identifyFile(entry.name, () => entry.content)) {
          case FileType.binary: _files.add(new ArchiveFile(entryFullName, entry)); break;
          case FileType.zip: _files.add(new ArchiveZipFile(entryFullName, entry)); break;
          case FileType.tar: _files.add(new ArchiveTarFile(entryFullName, entry)); break;
          case FileType.gz: _files.add(new ArchiveGZipFile(entryFullName, entry)); break;
          case FileType.bzip2: _files.add(new ArchiveBZip2File(entryFullName, entry)); break;
          case FileType.text: _files.add(new ArchiveUTF8TextFile(entryFullName, entry)); break;
          case FileType.latin1Text: _files.add(new ArchiveLatin1TextFile(entryFullName, entry)); break;
        }
      }
    }
  }

  static ArchiveDirectory parseArchive(a.Archive archive, String ownerPath) {
    final ArchiveDirectory root = new ArchiveDirectory('$ownerPath!', '');
    for (a.ArchiveFile file in archive.files) {
      if (file.size > 0)
        root._add(file, file.name.split('/'));
    }
    return root;
  }

  @override
  Iterable<IoNode> get walk sync* {
    yield* _subdirectories.values;
    yield* _files;
  }
}

class ArchiveFile extends IoNode implements File {
  ArchiveFile(this.fullName, this._file);

  final a.ArchiveFile _file;

  @override
  String get name => path.basename(_file.name);

  @override
  final String fullName;

  @override
  List<int> readBytes() {
    return _file.content;
  }
}

class ArchiveUTF8TextFile extends ArchiveFile with UTF8TextFile {
  ArchiveUTF8TextFile(String fullName, a.ArchiveFile file) : super(fullName, file);
}

class ArchiveLatin1TextFile extends ArchiveFile with Latin1TextFile {
  ArchiveLatin1TextFile(String fullName, a.ArchiveFile file) : super(fullName, file);
}

class ArchiveZipFile extends ArchiveFile with ZipFile {
  ArchiveZipFile(String fullName, a.ArchiveFile file) : super(fullName, file);
}

class ArchiveTarFile extends ArchiveFile with TarFile {
  ArchiveTarFile(String fullName, a.ArchiveFile file) : super(fullName, file);
}

class ArchiveGZipFile extends ArchiveFile with GZipFile {
  ArchiveGZipFile(String fullName, a.ArchiveFile file) : super(fullName, file);
}

class ArchiveBZip2File extends ArchiveFile with BZip2File {
  ArchiveBZip2File(String fullName, a.ArchiveFile file) : super(fullName, file);
}


// IN-MEMORY FILES (e.g. contents of GZipped files)

class InMemoryFile extends IoNode implements File {
  InMemoryFile(this.fullName, this._bytes);

  static InMemoryFile parse(String fullName, List<int> bytes) {
    if (bytes.isEmpty)
      return null;
    switch (identifyFile(fullName, () => bytes)) {
      case FileType.binary: return new InMemoryFile(fullName, bytes); break;
      case FileType.zip: return new InMemoryZipFile(fullName, bytes); break;
      case FileType.tar: return new InMemoryTarFile(fullName, bytes); break;
      case FileType.gz: return new InMemoryGZipFile(fullName, bytes); break;
      case FileType.bzip2: return new InMemoryBZip2File(fullName, bytes); break;
      case FileType.text: return new InMemoryUTF8TextFile(fullName, bytes); break;
      case FileType.latin1Text: return new InMemoryLatin1TextFile(fullName, bytes); break;
    }
    assert(false);
    return null;
  }

  @override
  final List<int> _bytes;


  @override
  String get name => '<data>';

  @override
  final String fullName;

  @override
  List<int> readBytes() => _bytes;
}

class InMemoryUTF8TextFile extends InMemoryFile with UTF8TextFile {
  InMemoryUTF8TextFile(String fullName, List<int> file) : super(fullName, file);
}

class InMemoryLatin1TextFile extends InMemoryFile with Latin1TextFile {
  InMemoryLatin1TextFile(String fullName, List<int> file) : super(fullName, file);
}

class InMemoryZipFile extends InMemoryFile with ZipFile {
  InMemoryZipFile(String fullName, List<int> file) : super(fullName, file);
}

class InMemoryTarFile extends InMemoryFile with TarFile {
  InMemoryTarFile(String fullName, List<int> file) : super(fullName, file);
}

class InMemoryGZipFile extends InMemoryFile with GZipFile {
  InMemoryGZipFile(String fullName, List<int> file) : super(fullName, file);
}

class InMemoryBZip2File extends InMemoryFile with BZip2File {
  InMemoryBZip2File(String fullName, List<int> file) : super(fullName, file);
}
