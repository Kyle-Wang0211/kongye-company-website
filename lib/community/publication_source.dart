/// Source identity shared by publication upload and preview. Changing format
/// changes the staging object identity even when the byte digest is unchanged.
enum PublicationSourceFormat {
  glb('model/gltf-binary'),
  ply('application/octet-stream');

  const PublicationSourceFormat(this.contentType);
  final String contentType;
  String get extension => name;

  static PublicationSourceFormat? fromFileName(String name) {
    final lower = name.toLowerCase();
    for (final format in values) {
      if (lower.endsWith('.${format.extension}')) return format;
    }
    return null;
  }
}

/// Uploads the exact immutable source whose digest was submitted. Completion
/// means the underlying transfer settled, even if the caller already timed out.
typedef PublicationUpload =
    Future<void> Function({
      required String path,
      required String token,
      required String bucket,
      void Function(int sent, int total)? onBytesSent,
    });
