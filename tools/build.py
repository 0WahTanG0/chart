#!/usr/bin/env python3
"""Собирает публичные файлы графика смен из web/index.html.

dist/web/index.html            — страница без личных данных (itch.io, обновление приложения)
dist/grafik-smen-itch-X.zip    — архив для загрузки на itch.io
dist/version.json              — описание последней версии для приложения Android
android/app/src/main/assets/web/index.html — страница, встроенная в APK

APK собирается отдельно: cd android && gradle assembleRelease
"""
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC_REPO_RAW = 'https://raw.githubusercontent.com/0WahTanG0/grafik-smen/main'
# Имена из личного списка: если хоть одно попадёт в публичную сборку, сборка останавливается.
PRIVATE_MARKERS = ['Софа', 'Зарина', 'Карина', 'Алина', 'Полина']


def main():
    src = (ROOT / 'web' / 'index.html').read_text(encoding='utf-8')
    page = re.sub(r'// @personal-start\n.*?// @personal-end\n', '', src, flags=re.S)
    page = page.replace("BUILD_TARGET = 'artifact'", "BUILD_TARGET = 'web'")
    leaked = [m for m in PRIVATE_MARKERS if m in page]
    if leaked or "BUILD_TARGET = 'web'" not in page:
        sys.exit(f'Сборка остановлена: личные данные в публичной странице ({", ".join(leaked)}) или нет метки сборки')

    version = re.search(r"APP_VERSION = '([^']+)'", page).group(1)
    web_build = int(re.search(r'WEB_BUILD = (\d+)', page).group(1))
    props = dict(line.split('=', 1) for line in (ROOT / 'android' / 'version.properties').read_text().splitlines()
                 if '=' in line and not line.startswith('#'))
    notes = (ROOT / 'tools' / 'notes.txt').read_text(encoding='utf-8').strip()

    dist = ROOT / 'dist'
    shutil.rmtree(dist, ignore_errors=True)
    (dist / 'web').mkdir(parents=True)
    (dist / 'web' / 'index.html').write_text(page, encoding='utf-8')
    assets = ROOT / 'android' / 'app' / 'src' / 'main' / 'assets' / 'web'
    assets.mkdir(parents=True, exist_ok=True)
    (assets / 'index.html').write_text(page, encoding='utf-8')

    with zipfile.ZipFile(dist / f'grafik-smen-itch-{version}.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('index.html', page)

    info = {
        'apkVersionCode': int(props['versionCode']),
        'apkVersionName': props['versionName'].strip(),
        'apkUrl': f'{PUBLIC_REPO_RAW}/grafik-smen.apk',
        'webBuild': web_build,
        'webVersion': version,
        'webUrl': f'{PUBLIC_REPO_RAW}/index.html',
        'notes': notes,
    }
    shutil.copy(ROOT / 'tools' / 'public-README.md', dist / 'README.md')
    (dist / 'version.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Готово: веб {version} (сборка {web_build}), APK {info["apkVersionName"]} (код {info["apkVersionCode"]})')


if __name__ == '__main__':
    main()
