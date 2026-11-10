/// Resolve only the server's visibility-checked publication cover endpoint.
String? publicationCoverUrl(Uri apiOrigin, String path) {
  if (apiOrigin.scheme != 'https' ||
      !RegExp(
        r'^/functions/v1/publication-cover[?]work_id=[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
      ).hasMatch(path)) {
    return null;
  }
  return Uri.parse(apiOrigin.origin).resolve(path).toString();
}
