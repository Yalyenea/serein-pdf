from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys

from bs4 import BeautifulSoup

root = Path(__file__).resolve().parents[1] / 'Website'
pages = {path: BeautifulSoup(path.read_text(), 'html.parser') for path in root.glob('*.html')}
script = (root / 'assets/main.js').read_text()
styles = root / 'assets/styles.css'
errors = []
for path, soup in pages.items():
    def require(condition, message):
        if not condition:
            errors.append(f'{path.name}: {message}')

    require(len(soup.find_all('h1')) == 1, 'expected one page heading')
    require(soup.select_one('[data-lang-toggle]') is not None, 'missing language control')
    require(soup.select_one('[data-theme-toggle]') is not None, 'missing theme control')
    ids = [el['id'] for el in soup.select('[id]')]
    require(len(ids) == len(set(ids)), 'duplicate element ID')
    for attr in ('data-i18n', 'data-i18n-html', 'data-i18n-attr'):
        for el in soup.select(f'[{attr}]'):
            key = el[attr].split(':')[-1]
            require(script.count(f'"{key}":') == 2, f'incomplete translation: {key}')
            require(attr != 'data-i18n' or el.find() is None, f'plain-text translation drops markup: {key}')
    image = soup.select_one('meta[property="og:image"]')
    require(image is not None and (root / urlsplit(image['content']).path.lstrip('/')).is_file(), 'missing share image')
    for el in soup.select('[src], [srcset], [href]'):
        url = urlsplit(el.get('src') or el.get('srcset') or el['href'])
        if url.scheme or url.netloc:
            continue
        target = (path.parent / unquote(url.path)).resolve() if url.path else path
        if target.is_dir():
            target /= 'index.html'
        require(target.is_relative_to(root) and target.is_file(), f'missing local target: {url.geturl()}')
        if url.fragment and target in pages:
            require(pages[target].find(id=unquote(url.fragment)) is not None, f'missing anchor: {url.geturl()}')

for ref in re.findall(r'url\("?([^")]+)', styles.read_text()):
    if not ref.startswith('data:') and not (styles.parent / ref).is_file():
        errors.append(f'{styles.name}: missing local target: {ref}')
if root / 'index.html' not in pages:
    errors.append('missing index.html')
if errors:
    sys.exit('\n'.join(errors))
print('Website check passed: local assets, links, anchors, and translations.')
