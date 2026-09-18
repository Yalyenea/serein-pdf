from pathlib import Path
from urllib.parse import unquote, urlsplit
import sys
import xml.etree.ElementTree as ET

from bs4 import BeautifulSoup

root = Path(__file__).resolve().parents[1] / 'Website'
pages = {path: BeautifulSoup(path.read_text(), 'html.parser') for path in root.glob('*.html')}
errors = []
for path, soup in pages.items():
    def require(condition, message):
        if not condition:
            errors.append(f'{path.name}: {message}')

    require(len(soup.find_all('h1')) == 1, 'expected one page heading')
    require(soup.select_one('main#main') is not None, 'missing main landmark')
    require(soup.select_one('.github-bar') is not None, 'missing GitHub bar')
    require(soup.select_one('[data-lang-toggle]') is not None, 'missing language control')
    require(soup.select_one('[data-theme-toggle]') is not None, 'missing theme control')
    require(len(soup.select('header [aria-current="page"]')) == 1, 'missing current navigation item')
    require(not soup.select('img, video, iframe'), 'unexpected screenshot, video, or embedded content')
    ids = [el['id'] for el in soup.select('[id]')]
    require(len(ids) == len(set(ids)), 'duplicate element ID')
    for el in soup.select('[data-en], [data-zh]'):
        require(bool(el.get('data-en')) and bool(el.get('data-zh')), 'incomplete translation')
    for el in soup.select('[src], [href]'):
        url = urlsplit(el.get('src') or el['href'])
        if url.scheme or url.netloc:
            continue
        target = (path.parent / unquote(url.path)).resolve() if url.path else path
        if target.is_dir():
            target /= 'index.html'
        require(target.is_relative_to(root) and target.is_file(), f'missing local target: {url.geturl()}')
        if url.fragment and target in pages:
            require(pages[target].find(id=unquote(url.fragment)) is not None, f'missing anchor: {url.geturl()}')
    canonical = soup.select_one('link[rel="canonical"]')
    expected = 'https://serein.yfff.me/' + ('' if path.name == 'index.html' else path.name)
    require(canonical is not None and canonical.get('href') == expected, 'incorrect canonical URL')

for required in ('index.html', 'changelog.html', 'docs.html', 'assets/styles.css', 'assets/main.js', 'assets/app-icon.png', 'robots.txt', 'sitemap.xml'):
    if not (root / required).is_file():
        errors.append(f'missing {required}')

sitemap = ET.parse(root / 'sitemap.xml')
urls = {el.text for el in sitemap.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')}
expected_urls = {'https://serein.yfff.me/' + ('' if path.name == 'index.html' else path.name) for path in pages}
if urls != expected_urls:
    errors.append('sitemap does not match website pages')
if errors:
    sys.exit('\n'.join(errors))
print(f'Website check passed: {len(pages)} pages, local links, translations, navigation, and sitemap.')
