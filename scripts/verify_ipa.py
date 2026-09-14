#!/usr/bin/env python3
"""Check CI editor IPA structure, plist, CRCs and executable permissions."""
import plistlib
import stat
import sys
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'ZIP CRC failure'
        names = archive.namelist()
        assert len(names) == len(set(names)), 'Duplicate ZIP paths'
        roots = {p.split('/')[1] for p in names if p.startswith('Payload/') and len(p.split('/')) > 2}
        assert roots == {'ModMyIPA.app'}, roots
        info = plistlib.loads(archive.read('Payload/ModMyIPA.app/Info.plist'))
        assert info['CFBundleIdentifier'] == 'org.ipaeditor.VersionEditor', info
        assert info['MinimumOSVersion'] == '15.0', info
        assert info['CFBundleShortVersionString'] == '1.1.0', info
        executable = 'Payload/ModMyIPA.app/' + info['CFBundleExecutable']
        assert archive.read(executable)[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'), 'Not arm64 Mach-O/universal'
        mode = archive.getinfo(executable).external_attr >> 16
        assert mode & stat.S_IXUSR, 'Executable permission lost'
        assert info.get('UIFileSharingEnabled') is True
        assert info.get('LSSupportsOpeningDocumentsInPlace') is True
    print('Verified:', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit('Usage: verify_ipa.py editor.ipa [other.ipa]')
    for path in sys.argv[1:]:
        verify(path)
