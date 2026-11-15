import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Save and share helpers for exported history JSON.
abstract final class HistoryExport {
  static const String fileName = 'anime-tui-history.json';

  /// Ask the user for a folder/name with the system save dialog and write
  /// [data] there. Returns the saved location, or null when canceled.
  static Future<Uri?> saveJson(String data) {
    return FilePicker.saveFile(
      dialogTitle: 'Export history',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(data)),
      mimeType: 'application/json',
    );
  }

  /// Write [data] to a temporary file and open the system share sheet.
  ///
  /// Returns true when the user picked a destination app.
  static Future<bool> shareJson(String data) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(data, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, mimeType: 'application/json'),
        ],
        subject: 'Anime TUI watch history',
        text: 'Watch history exported from Anime TUI.',
        title: 'Share history',
      ),
    );
    return result.status == ShareResultStatus.success;
  }

  /// Short label for the location picked in the save dialog.
  static String describeLocation(Uri uri) {
    if (uri.scheme == 'file') return uri.toFilePath();
    return 'the selected folder';
  }
}
