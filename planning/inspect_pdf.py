from pathlib import Path
import pypdfium2 as pdfium
from pypdf import PdfReader
from PIL import Image, ImageOps, ImageDraw

root=Path(__file__).resolve().parent/'qa'
pdf=root/'plan.pdf'
reader=PdfReader(str(pdf))
print('PAGES',len(reader.pages))
for i,p in enumerate(reader.pages):
    text=p.extract_text() or ''
    (root/f'page-{i+1}.txt').write_text(text,encoding='utf-8')
    print(i+1,len(text),text[:75].replace('\n',' '))
doc=pdfium.PdfDocument(str(pdf))
thumbs=[]
for i in range(len(doc)):
    page=doc[i]
    bitmap=page.render(scale=1.7)
    im=bitmap.to_pil().convert('RGB')
    im.save(root/f'page-{i+1}.png')
    thumb=im.copy(); thumb.thumbnail((360,510))
    tile=Image.new('RGB',(380,540),'#dddddd')
    tile.paste(thumb,((380-thumb.width)//2,10))
    ImageDraw.Draw(tile).text((12,520),f'Page {i+1}',fill='black')
    thumbs.append(tile)
for offset in range(0,len(thumbs),6):
    group=thumbs[offset:offset+6]
    sheet=Image.new('RGB',(380*3,540*2),'white')
    for j,im in enumerate(group): sheet.paste(im,((j%3)*380,(j//3)*540))
    sheet.save(root/f'contact-{offset//6+1}.png')
