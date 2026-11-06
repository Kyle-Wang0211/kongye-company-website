#!/usr/bin/env python3
"""Build a test-only native WebView APK using existing SDK tools, without Gradle.

No installation, signing, SDK download, dependency resolution or product mutation.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent
WEB = HERE.parents[1] / 'web'
JAVA_PACKAGE = 'dev.pocketworld.sharedviewerfixture'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_bundle():
    manifest = json.loads((WEB / 'BUNDLE_MANIFEST.json').read_text())
    files = manifest.get('files')
    required = {'index.html', 'viewer.mjs', 'host_bridge.mjs', 'bundle_identity.mjs',
                'skp_import.mjs', 'skp_import_worker.mjs', 'skp_policy.mjs',
                'vendor/openskp/openskp-browser.mjs'}
    if (manifest.get('schema') != 'PW_SHARED_VIEWER_BUNDLE_V1' or
            manifest.get('engine') != 'three' or manifest.get('engine_version') != '0.186.1' or
            manifest.get('upstream_commit') != '9b4a2ac29c63ccb43fd51c5661f2f873ac2c39b8' or
            not isinstance(files, dict) or not required.issubset(files)):
        raise RuntimeError('Expected shared engine/SKP bundle resources are missing from manifest')
    canonical = json.dumps(files, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
    if hashlib.sha256(canonical).hexdigest() != manifest.get('bundle_sha256'):
        raise RuntimeError('Shared bundle canonical identity mismatch')
    for relative, expected in files.items():
        file = WEB / relative
        if (not relative or relative.startswith('/') or '\\' in relative or
                any(p in ('', '.', '..') for p in relative.split('/')) or
                file.is_symlink() or not file.is_file() or
                not file.resolve().is_relative_to(WEB.resolve()) or sha(file) != expected):
            raise RuntimeError('Shared resource identity mismatch: ' + relative)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path, help='New isolated output directory')
    parser.add_argument('--sdk', type=Path, default=Path.home() / 'Library/Android/sdk')
    parser.add_argument('--java-home', type=Path, default=Path('/opt/homebrew/opt/openjdk'))
    args = parser.parse_args()
    out = args.out.expanduser().resolve()
    if out.exists():
        raise RuntimeError('Output directory already exists; preserve it and choose a fresh build directory')
    if out.is_relative_to(HERE.parents[3]):
        raise RuntimeError('Build outside the product repository')
    tools = args.sdk / 'build-tools/34.0.0'
    android_jar = args.sdk / 'platforms/android-34/android.jar'
    java = args.java_home / 'bin/java'
    javac = args.java_home / 'bin/javac'
    inputs = [android_jar, java, javac, tools / 'aapt', tools / 'lib/d8.jar', tools / 'zipalign', tools / 'core-lambda-stubs.jar']
    for item in inputs:
        if not item.is_file():
            raise RuntimeError('Missing existing build input: ' + str(item))
    manifest = verify_bundle()  # Fail before staging or compilation if identity is stale.
    out.mkdir(parents=True)
    evidence = {'schema': 'PW_NATIVE_ANDROID_APK_BUILD_V1', 'status': 'running',
                'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'bundle_sha256': manifest['bundle_sha256'], 'application_id': JAVA_PACKAGE,
                'min_sdk': 26, 'target_sdk': 34, 'signed': False, 'installed': False,
                'build_inputs': {str(p): sha(p) for p in inputs}, 'steps': [],
                'source_inputs': {str(p.relative_to(HERE)): sha(p) for p in HERE.rglob('*') if p.is_file()}}
    log = (out / 'build.log').open('w')

    def run(argv, cwd=out, expected=0):
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        result = subprocess.run([str(v) for v in argv], cwd=cwd, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log.write('$ ' + ' '.join(str(v) for v in argv) + '\n' + result.stdout + '\n')
        log.flush()
        print(result.stdout, end='')
        evidence['steps'].append({'argv': [str(v) for v in argv], 'cwd': str(cwd),
                                  'started_at': started,
                                  'ended_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                  'exit_code': result.returncode})
        if result.returncode != expected:
            raise RuntimeError('Build step failed: ' + str(argv[0]))
        return result.stdout

    try:
        assets = out / 'assets/pw_shared_viewer'
        assets.mkdir(parents=True)
        for relative in [*manifest['files'], 'BUNDLE_MANIFEST.json']:
            target = assets / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(WEB / relative, target)
        paths = sorted([*manifest['files'], 'BUNDLE_MANIFEST.json'])
        generated = out / 'generated/dev/pocketworld/sharedviewerfixture'
        generated.mkdir(parents=True)
        (generated / 'BundleAssets.java').write_text(
            'package ' + JAVA_PACKAGE + ';\n' +
            'import java.util.*;\npublic final class BundleAssets {\n' +
            ' public static final String IDENTITY = ' + json.dumps(manifest['bundle_sha256']) + ';\n' +
            ' public static final Set<String> PATHS = Collections.unmodifiableSet(new HashSet<String>(Arrays.asList(\n' +
            ',\n'.join(json.dumps(p) for p in paths) + ')));\n}\n')
        classes = out / 'classes'
        dex = out / 'dex'
        classes.mkdir()
        dex.mkdir()
        run([java, '-version'])
        run([javac, '-version'])
        run([tools / 'aapt', 'version'])
        run([tools / 'aapt', 'package', '-f', '-M', HERE / 'AndroidManifest.xml', '-I', android_jar,
             '-A', out / 'assets', '-F', out / 'base.apk'])
        sources = sorted((HERE / 'src').rglob('*.java')) + [generated / 'BundleAssets.java']
        run([javac, '-parameters', '-source', '8', '-target', '8', '-bootclasspath', str(android_jar) + os.pathsep + str(tools / 'core-lambda-stubs.jar'),
             '-d', classes, *sources])
        run([java, '-Xmx512m', '-cp', tools / 'lib/d8.jar', 'com.android.tools.r8.D8',
             '--lib', android_jar, '--min-api', '26', '--output', dex, *sorted(classes.rglob('*.class'))])
        run([tools / 'aapt', 'add', out / 'base.apk', 'classes.dex'], cwd=dex)
        apk = out / 'pw-shared-viewer-native-unsigned.apk'
        run([tools / 'zipalign', '-f', '4', out / 'base.apk', apk])
        run([tools / 'zipalign', '-c', '4', apk])
        badging = run([tools / 'aapt', 'dump', 'badging', apk])
        (out / 'apk-badging.txt').write_text(badging)
        with zipfile.ZipFile(apk) as archive:
            if not archive.read('classes.dex').startswith(b'dex\n'):
                raise RuntimeError('APK lacks valid DEX header')
            if any(p.startswith('META-INF/') for p in archive.namelist()):
                raise RuntimeError('Unexpected APK signing metadata')
            packaged = {p for p in archive.namelist() if p.startswith('assets/pw_shared_viewer/') and not p.endswith('/')}
            expected = {'assets/pw_shared_viewer/' + p for p in paths}
            if packaged != expected:
                raise RuntimeError('APK asset file set differs from verified bundle')
            for relative in paths:
                if archive.read('assets/pw_shared_viewer/' + relative) != (assets / relative).read_bytes():
                    raise RuntimeError('APK asset bytes differ: ' + relative)
        evidence.update(status='unsigned_apk_built', apk=str(apk), apk_sha256=sha(apk),
                        packaged_asset_count=len(paths),
                        limitations=['Not installed or executed', 'System WebView version/import maps/WebGL2/module worker behavior unverified',
                                     'No rendering or cross-platform visual parity claim'])
        print('UNSIGNED_APK_BUILT ' + str(apk))
    except Exception as failure:
        evidence.update(status='failed', error=str(failure))
        raise
    finally:
        evidence['ended_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out / 'BUILD_EVIDENCE.json').write_text(json.dumps(evidence, indent=2) + '\n')
        log.close()


if __name__ == '__main__':
    main()
