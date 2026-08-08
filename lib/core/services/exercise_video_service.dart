import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Upload result for one global-catalog video.
class ExerciseVideoUpload {
  /// The tokenized https download URL. This is what goes into
  /// `exerciseCatalog/{id}.videoUrl` and what every member's player fetches.
  final String downloadUrl;

  /// The full Storage object path, kept so a REPLACEMENT can delete the object
  /// it superseded instead of orphaning it.
  final String storagePath;

  final int sizeBytes;
  final String contentType;

  const ExerciseVideoUpload({
    required this.downloadUrl,
    required this.storagePath,
    required this.sizeBytes,
    required this.contentType,
  });
}

/// Raised for a refusal the OPERATOR can act on (wrong type, too large).
/// Distinguished from an infrastructure failure so the dialog can say which.
class ExerciseVideoRejected implements Exception {
  final String message;
  const ExerciseVideoRejected(this.message);
  @override
  String toString() => message;
}

/// THE upload path for global exercise demo videos.
///
/// WHY THIS EXISTS SEPARATELY FROM THE CATALOG CALLABLE. Bytes and metadata
/// travel by different roads: the object goes straight to Storage from the
/// browser (a callable cannot carry 50 MB), while the resulting URL is written
/// through `upsertGlobalExercise` like every other field. Keeping the two apart
/// is what lets a failed upload leave the Firestore document untouched — the
/// exercise is only ever saved with a URL that already resolves.
///
/// ⚠️ CONTENT TYPE IS SET EXPLICITLY AND THAT IS LOAD-BEARING. `storage.rules`
/// gates every write on `okMedia()`, which requires a non-null
/// `contentType` matching `video/*`. Firebase infers nothing useful from a
/// browser byte array, so an upload without explicit metadata is REJECTED by
/// the rules — silently, as a permission error rather than a validation one.
/// This platform has already shipped that exact defect once, on profile photos.
class ExerciseVideoService {
  ExerciseVideoService({FirebaseStorage? storage, FirebaseAuth? auth})
    : _storageOverride = storage,
      _authOverride = auth;

  // ⚠️ RESOLVED LAZILY, NOT IN A FIELD INITIALIZER.
  //
  // `FirebaseStorage.instance` throws `[core/no-app]` when no Firebase app has
  // been initialised. A field initializer runs at CONSTRUCTION, so a service
  // built that way explodes the moment its owner is constructed — which for
  // this class is `_ExerciseFormDialogState`, making the entire authoring
  // dialog impossible to mount in a widget test and taking the screen down in
  // any context without Firebase.
  //
  // This is a RECURRING defect class in this platform: TrainerService,
  // StorageService, HrService, ClientService, CloudFunctionsService and
  // SessionController each shipped it and each was fixed the same way. It was
  // reintroduced here and caught by `exercise_console_test.dart`, which failed
  // with exactly that error before this change.
  final FirebaseStorage? _storageOverride;
  final FirebaseAuth? _authOverride;

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  /// Mirrors `okMedia()` in storage.rules (< 50 MB). Enforced here too so the
  /// operator is told BEFORE a 50 MB upload spends their bandwidth and then
  /// bounces off a rule with an opaque permission error.
  static const int maxBytes = 50 * 1024 * 1024;

  /// Container formats a browser can actually play back. Deliberately narrower
  /// than the rules' `video/*`: a rule that admits any video codec is fine as a
  /// security boundary, but shipping a `.mkv` to a member's phone is a product
  /// defect, not a security one.
  static const List<String> allowedExtensions = ['mp4', 'mov', 'webm', 'm4v'];

  static const Map<String, String> _mimeByExtension = {
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
  };

  /// Resolves the MIME type from the FILE NAME, never from what the picker
  /// claims. Browsers report an empty or `application/octet-stream` type for
  /// perfectly valid videos, and that value would fail `okMedia()`.
  static String mimeFor(String fileName) {
    final ext = _extensionOf(fileName);
    return _mimeByExtension[ext] ?? 'video/mp4';
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Validates a candidate before a single byte is sent. Returns null when the
  /// file is acceptable, or an operator-facing reason when it is not.
  static String? rejectionReasonFor({
    required String fileName,
    required int sizeBytes,
  }) {
    final ext = _extensionOf(fileName);
    if (ext.isEmpty || !allowedExtensions.contains(ext)) {
      return 'Unsupported format ".$ext". Use MP4, MOV, WebM or M4V.';
    }
    if (sizeBytes <= 0) return 'That file is empty.';
    if (sizeBytes >= maxBytes) {
      final mb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
      return 'That file is $mb MB. The limit is 50 MB.';
    }
    return null;
  }

  /// The object path for a new upload.
  ///
  /// TIMESTAMPED, NEVER OVERWRITTEN IN PLACE. Replacing a video writes a NEW
  /// object and only then repoints the document, so a member mid-workout on the
  /// old URL is never served a half-written file. The superseded object is
  /// deleted afterwards by [deleteObject], which is why the caller keeps the
  /// old path around.
  ///
  /// The folder is the founder's own uid because that is the shape every other
  /// Storage rule in this platform uses; `callerIsSuperAdmin()` in the rule is
  /// what makes the folder platform-owned rather than personal.
  String pathFor(String fileName) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw const ExerciseVideoRejected('Not signed in.');
    }
    final ext = _extensionOf(fileName);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return 'exercise_catalog/$uid/${stamp}_video.${ext.isEmpty ? 'mp4' : ext}';
  }

  /// Uploads [bytes] and reports progress as a 0..1 fraction.
  ///
  /// Returns the tokenized download URL. Throws [ExerciseVideoRejected] for an
  /// operator-fixable refusal, or rethrows the Storage error otherwise so the
  /// dialog can distinguish "your file is wrong" from "the upload broke".
  Future<ExerciseVideoUpload> upload({
    required String fileName,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onTask,
  }) async {
    final reason = rejectionReasonFor(
      fileName: fileName,
      sizeBytes: bytes.lengthInBytes,
    );
    if (reason != null) throw ExerciseVideoRejected(reason);

    final path = pathFor(fileName);
    final contentType = mimeFor(fileName);
    final task = _storage.ref(path).putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        // Survives in object metadata so an operator staring at a bucket can
        // tell a catalog demo from anything else that lands here later.
        customMetadata: {'kind': 'global_exercise_video'},
      ),
    );
    // Handed to the caller so a CANCEL button can abort a large upload; without
    // it the dialog could only hide the progress bar while the bytes kept going.
    onTask?.call(task);

    if (onProgress != null) {
      task.snapshotEvents.listen(
        (s) {
          if (s.totalBytes > 0) {
            onProgress(s.bytesTransferred / s.totalBytes);
          }
        },
        // A failed upload surfaces through the awaited future below; a raw
        // listener error would otherwise become an unhandled zone exception.
        onError: (_) {},
      );
    }

    final snapshot = await task;
    final url = await snapshot.ref.getDownloadURL();
    return ExerciseVideoUpload(
      downloadUrl: url,
      storagePath: path,
      sizeBytes: bytes.lengthInBytes,
      contentType: contentType,
    );
  }

  /// Recovers the Storage object path from a tokenized download URL.
  ///
  /// WHY DERIVE IT RATHER THAN STORE IT. `EXERCISE_INPUT_FIELDS` is the
  /// server's closed list of writable fields and it has no `videoStoragePath`.
  /// Adding one would be a backend schema change, a validator change and a
  /// migration for 846 live rows — all to persist something the URL already
  /// contains. A download URL is
  /// `…/o/<url-encoded-object-path>?alt=media&token=…`, so the path is simply
  /// the decoded segment between `/o/` and the query string.
  ///
  /// Returns '' for anything that is not a Firebase Storage URL — a manually
  /// pasted third-party link has no object for us to delete, and must not be
  /// mistaken for one.
  static String storagePathFromUrl(String url) {
    if (url.isEmpty) return '';
    final marker = url.indexOf('/o/');
    if (marker < 0) return '';
    var tail = url.substring(marker + 3);
    final query = tail.indexOf('?');
    if (query >= 0) tail = tail.substring(0, query);
    if (tail.isEmpty) return '';
    try {
      final decoded = Uri.decodeComponent(tail);
      // Only ever hand back a path inside OUR folder. A malformed or foreign
      // URL must never resolve to a delete against somebody else's object.
      return decoded.startsWith('exercise_catalog/') ? decoded : '';
    } catch (_) {
      return '';
    }
  }

  /// Deletes a superseded object. BEST EFFORT BY DESIGN.
  ///
  /// A failure here must never fail the save: the document already points at
  /// the new video and the member experience is correct. The worst case is one
  /// orphaned object, which is strictly better than refusing to update an
  /// exercise because its old file could not be tidied up.
  Future<void> deleteObject(String storagePath) async {
    if (storagePath.isEmpty) return;
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {
      // Intentionally swallowed — see above.
    }
  }
}
