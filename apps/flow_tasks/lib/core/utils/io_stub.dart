// Stub file for dart:io on web platforms

class File {
  final String path;
  File(this.path);

  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    return this;
  }

  Future<bool> exists() async => false;

  Future<void> delete() async {}
}

class Directory {
  final String path;
  Directory(this.path);

  Future<bool> exists() async => false;

  Future<Directory> create({bool recursive = false}) async {
    return this;
  }
}
