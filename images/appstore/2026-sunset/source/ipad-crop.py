import sys
from PIL import Image

d = sys.argv[1]
PAD = 420
W, H = 2097, 2796  # 0.75 aspect at the panorama's height
for i in range(5):
    im = Image.open(f"{d}/pano-{i + 1}.png").convert("RGB")
    pw, ph = im.size
    big = Image.new("RGB", (pw + 2 * PAD, ph))
    big.paste(im, (PAD, 0))
    # extend the outer edges by stretching the first and last 4 px columns
    big.paste(im.crop((0, 0, 4, ph)).resize((PAD, ph)), (0, 0))
    big.paste(im.crop((pw - 4, 0, pw, ph)).resize((PAD, ph)), (PAD + pw, 0))
    cx = PAD + i * 1290 + 645
    x0 = round(cx - W / 2)
    frame = big.crop((x0, 0, x0 + W, H)).resize((2064, 2752), Image.LANCZOS)
    frame.save(f"{d}/ipad-{i + 1}.png")
    print(i + 1, frame.size)
