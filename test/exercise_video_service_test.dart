import 'package:alphaserena_admin_portel/core/services/exercise_video_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// GLOBAL EXERCISE VIDEO — the pure half of the upload path.
///
/// Everything here runs without Firebase, which is itself the point: the
/// service used to resolve `FirebaseStorage.instance` in a field initializer
/// and therefore could not be CONSTRUCTED in a test at all. That defect is the
/// reason this file exists.
void main() {
  group('construction', () {
    test('the service can be built with no Firebase app initialised', () {
      // The regression guard. If this throws `[core/no-app]` again, the lazy
      // getters have been turned back into field initializers — the exact
      // defect that has now shipped seven times in this platform.
      expect(ExerciseVideoService.new, returnsNormally);
    });
  });

  group('content type', () {
    test('is resolved from the FILE NAME, never from the picker', () {
      // Browsers routinely report '' or application/octet-stream for a valid
      // video. `okMedia()` in storage.rules requires a non-null `video/*`
      // contentType, so trusting the picker is what makes an upload bounce off
      // the rules as an opaque permission error.
      expect(ExerciseVideoService.mimeFor('squat.mp4'), 'video/mp4');
      expect(ExerciseVideoService.mimeFor('squat.MP4'), 'video/mp4');
      expect(ExerciseVideoService.mimeFor('squat.mov'), 'video/quicktime');
      expect(ExerciseVideoService.mimeFor('squat.webm'), 'video/webm');
      expect(ExerciseVideoService.mimeFor('squat.m4v'), 'video/mp4');
    });

    test('an unknown extension still yields a rules-satisfying video type', () {
      // Belt and braces: rejection happens first, so this path is only ever
      // reached for something already accepted. It must never return ''.
      expect(ExerciseVideoService.mimeFor('noextension'), startsWith('video/'));
    });
  });

  group('validation refuses before a byte is sent', () {
    test('an unsupported container is named, not silently accepted', () {
      final reason = ExerciseVideoService.rejectionReasonFor(
        fileName: 'clip.mkv',
        sizeBytes: 1024,
      );
      expect(reason, isNotNull);
      expect(reason, contains('mkv'));
      expect(reason, contains('MP4'));
    });

    test('an executable disguised by size is refused on its extension', () {
      expect(
        ExerciseVideoService.rejectionReasonFor(
          fileName: 'payload.exe',
          sizeBytes: 2048,
        ),
        isNotNull,
      );
    });

    test('a file at or over 50 MB is refused with its real size', () {
      final reason = ExerciseVideoService.rejectionReasonFor(
        fileName: 'huge.mp4',
        sizeBytes: 50 * 1024 * 1024,
      );
      expect(reason, isNotNull);
      // The operator is told what they picked AND what the limit is; "too
      // large" alone leaves them guessing how much to compress.
      expect(reason, contains('50.0 MB'));
      expect(reason, contains('limit is 50 MB'));
    });

    test('an empty file is refused', () {
      expect(
        ExerciseVideoService.rejectionReasonFor(
          fileName: 'empty.mp4',
          sizeBytes: 0,
        ),
        isNotNull,
      );
    });

    test('a valid video just under the cap is accepted', () {
      expect(
        ExerciseVideoService.rejectionReasonFor(
          fileName: 'demo.mp4',
          sizeBytes: 50 * 1024 * 1024 - 1,
        ),
        isNull,
      );
    });
  });

  group('storagePathFromUrl — replacement cleanup', () {
    test('recovers the object path from a tokenized download URL', () {
      // The real shape Firebase returns. The path segment is percent-encoded,
      // which is why this cannot be a naive substring split on '/'.
      const url =
          'https://firebasestorage.googleapis.com/v0/b/trainershq-f5ded'
          '.firebasestorage.app/o/exercise_catalog%2Fabc123%2F1699_video.mp4'
          '?alt=media&token=deadbeef-0000';
      expect(
        ExerciseVideoService.storagePathFromUrl(url),
        'exercise_catalog/abc123/1699_video.mp4',
      );
    });

    test('refuses to resolve a path outside our own folder', () {
      // A delete built from a foreign URL would be a cross-tenant destruction.
      const url =
          'https://firebasestorage.googleapis.com/v0/b/x/o/'
          'hr_documents%2Forg1%2Fuid1%2Fpayslip.pdf?alt=media&token=t';
      expect(ExerciseVideoService.storagePathFromUrl(url), '');
    });

    test('a pasted third-party URL resolves to nothing to delete', () {
      expect(
        ExerciseVideoService.storagePathFromUrl(
          'https://cdn.example.com/bench.mp4',
        ),
        '',
      );
      expect(ExerciseVideoService.storagePathFromUrl(''), '');
    });

    test('a malformed URL never throws', () {
      // Called on every save; an exception here would fail an otherwise good
      // write for the sake of housekeeping.
      expect(
        () => ExerciseVideoService.storagePathFromUrl('https://x/o/%%%bad'),
        returnsNormally,
      );
    });
  });
}
