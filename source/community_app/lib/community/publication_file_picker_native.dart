import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// Retains the plugin's native file path rather than loading its bytes.
Future<XFile?> pickPublicationFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['glb', 'ply'],
    withData: false,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  if (file.path == null || file.path!.isEmpty) {
    throw StateError('Selected publication file has no readable local path');
  }
  return XFile(file.path!, name: file.name, length: file.size);
}
