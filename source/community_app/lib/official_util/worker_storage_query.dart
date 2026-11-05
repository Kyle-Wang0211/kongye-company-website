import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Exact Apple LP64 SDK sys/statvfs.h layout (64 bytes, alignment 8).
/// Importantly fsblkcnt_t/fsfilcnt_t are UINT32, even on arm64.
/// All offsets/types were compiled against iPhoneOS and macOS SDK headers:
/// offsets 0,8,16,20,24,28,32,36,40,48,56. No Android/Linux ABI claim.
final class Apple64Statvfs extends Struct {
  @UnsignedLong()
  external int blockSize;
  @UnsignedLong()
  external int fragmentSize;
  @Uint32()
  external int blocks;
  @Uint32()
  external int freeBlocks;
  @Uint32()
  external int availableBlocks;
  @Uint32()
  external int files;
  @Uint32()
  external int freeFiles;
  @Uint32()
  external int availableFiles;
  @UnsignedLong()
  external int filesystemId;
  @UnsignedLong()
  external int flags;
  @UnsignedLong()
  external int nameMax;
}

typedef StatvfsNativeQuery =
    int Function(Pointer<Utf8>, Pointer<Apple64Statvfs>);
typedef _StatvfsC = Int32 Function(Pointer<Utf8>, Pointer<Apple64Statvfs>);

/// Actual free disk bytes available to the app, not RAM or purgeable estimates.
/// [path] must exist on the destination filesystem. Every call queries libc
/// statvfs anew; no Flutter channel, custom native library or caching is used.
/// The verified ABI is Apple LP64 only; unsupported/error results always throw.
/// [nativeQuery] is solely for deterministic syscall-result tests.
int readAvailableStorageInWorker(
  String path, {
  StatvfsNativeQuery? nativeQuery,
}) {
  final encoded = utf8.encode(path);
  // Path + 64-byte statvfs buffer remain below 1 KiB total native allocation.
  if (!path.startsWith('/') || encoded.contains(0) || encoded.length > 959) {
    throw ArgumentError.value(
      path,
      'path',
      'Expected absolute UTF-8 path <=959 bytes without NUL',
    );
  }
  try {
    final abi = Abi.current();
    if (!(Platform.isIOS || Platform.isMacOS) ||
        ![Abi.iosArm64, Abi.macosArm64, Abi.macosX64].contains(abi) ||
        sizeOf<Apple64Statvfs>() != 64) {
      throw UnsupportedError('Unverified statvfs ABI');
    }
    final query =
        nativeQuery ??
        DynamicLibrary.process().lookupFunction<_StatvfsC, StatvfsNativeQuery>(
          'statvfs',
        );
    return using((arena) {
      final buffer = arena<Apple64Statvfs>();
      final status = query(path.toNativeUtf8(allocator: arena), buffer);
      if (status != 0) throw StateError('statvfs failed');
      final size = buffer.ref.fragmentSize;
      final blocks = buffer.ref.availableBlocks;
      // POSIX defines block counts in f_frsize units, not f_bsize units.
      // Reject zero/malformed size and overflow instead of wrapping disk bytes.
      if (size <= 0 ||
          blocks < 0 ||
          size > 0x7fffffffffffffff ||
          blocks > 0x7fffffffffffffff ~/ size) {
        throw StateError('Invalid or overflowing statvfs measurement');
      }
      return blocks * size;
    });
  } catch (error) {
    throw StateError('可用存储空间读取失败，已停止生成，请稍后重试 ($error)');
  }
}
