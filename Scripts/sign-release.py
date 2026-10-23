#!/usr/bin/env python3
"""Sign the exact downloaded release archive and generate updates/appcast.xml."""
import os
import plistlib
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

root = Path(__file__).resolve().parents[1]
if len(sys.argv) != 3:
    raise SystemExit('Usage: sign-release.py /path/to/release.zip /secure/path/to/private.key')
archive, key = (Path(arg).resolve() for arg in sys.argv[1:])
signer = Path(os.environ.get('STUDYPILOT_SIGN_UPDATE', root / '.build-local/build/artifacts/sparkle/Sparkle/bin/sign_update'))
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
signature = subprocess.check_output([str(signer), '--ed-key-file', str(key), '-p', str(archive)], text=True).strip()
subprocess.run([str(signer), '--ed-key-file', str(key), '--verify', str(archive), signature], check=True)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
feed = ET.Element('rss', version='2.0')
channel = ET.SubElement(feed, 'channel')
ET.SubElement(channel, 'title').text = 'StudyPilot updates'
item = ET.SubElement(channel, 'item')
version = info['CFBundleShortVersionString']
ET.SubElement(item, 'title').text = 'StudyPilot ' + version
ET.SubElement(item, '{%s}minimumSystemVersion' % ns).text = '14.0'
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/Sumi1124/StudyPilot/releases/download/v{version}/StudyPilot-macOS.zip',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    '{%s}version' % ns: info['CFBundleVersion'],
    '{%s}shortVersionString' % ns: version,
    '{%s}edSignature' % ns: signature,
})
(root / 'updates').mkdir(exist_ok=True)
ET.indent(feed)
ET.ElementTree(feed).write(root / 'updates/appcast.xml', encoding='utf-8', xml_declaration=True)
print('Verified archive signature and wrote updates/appcast.xml.')
