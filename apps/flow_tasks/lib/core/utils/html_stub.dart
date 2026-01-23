// Stub file for dart:html on non-web platforms
class AnchorElement {
  String? href;
  String? download;
  void click() {}
  void remove() {}
}

class Blob {
  Blob(List<dynamic> parts, [Map<String, String>? options]);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class document {
  static final body = _Body();
}

class _Body {
  void append(dynamic element) {}
}
