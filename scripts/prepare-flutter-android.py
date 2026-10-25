"""Install exact official Android build packages with published SHA-1 verification."""
from pathlib import Path
import urllib.request,xml.etree.ElementTree as ET,json,hashlib,zipfile,concurrent.futures,shutil
root=Path(__file__).resolve().parent.parent
sdk=root/'.tools/android-sdk'
packages=json.loads((root/'.tools/downloads/flutter-android-packages.json').read_text())
def install(package):
    path=root/'.tools/downloads'/package['url'].split('/')[-1]
    if not path.exists() or path.stat().st_size!=int(package['size']):urllib.request.urlretrieve(package['url'],path)
    with path.open('rb') as stream:
        actual=hashlib.file_digest(stream,'sha1').hexdigest()
    if actual!=package['checksum']:raise ValueError('Official checksum mismatch: '+package['path'])
    destination=sdk/Path(*package['path'].split(';'))
    if not (destination/'source.properties').exists():
        destination.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                parts=Path(info.filename).parts[1:]
                if not parts:continue
                target=destination.joinpath(*parts)
                if not target.resolve().is_relative_to(destination.resolve()):raise ValueError('Invalid archive path')
                if info.is_dir():target.mkdir(parents=True,exist_ok=True)
                else:
                    target.parent.mkdir(parents=True,exist_ok=True)
                    with archive.open(info) as source,target.open('wb') as output:shutil.copyfileobj(source,output)
    print('Verified and installed '+package['path'],flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(install,packages))
