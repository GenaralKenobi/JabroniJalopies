# Regenerates the app icon: python3 scripts/make_icon.py VehicleMaintenance/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# Requires Pillow (pip install pillow).
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4  # supersample for smooth edges
N = S * SS

# Background: diagonal orange gradient
top = (250, 128, 60)
bottom = (214, 72, 36)
bg = Image.new("RGB", (N, N))
small = Image.new("L", (256, 256))
small.putdata([(x + y) // 2 for y in range(256) for x in range(256)])
grad = small.resize((N, N), Image.BILINEAR)
bg = Image.composite(Image.new("RGB", (N, N), bottom), Image.new("RGB", (N, N), top), grad)

# Wrench mask, drawn horizontally then rotated 45 degrees
mask = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(mask)
cx, cy = N // 2, N // 2
u = N / 1024
handle_len, handle_w = 560 * u, 120 * u
d.rounded_rectangle([cx - handle_len / 2, cy - handle_w / 2, cx + handle_len / 2, cy + handle_w / 2],
                    radius=handle_w / 2, fill=255)
# Open-end head on the left
hr = 165 * u
hx = cx - handle_len / 2
d.ellipse([hx - hr, cy - hr, hx + hr, cy + hr], fill=255)
jaw_w = 120 * u
d.rectangle([hx - hr - 10 * u, cy - jaw_w / 2, hx + 10 * u, cy + jaw_w / 2], fill=0)
# Ring head on the right
rr = 130 * u
rx = cx + handle_len / 2
d.ellipse([rx - rr, cy - rr, rx + rr, cy + rr], fill=255)
ir = 62 * u
d.regular_polygon((rx, cy, ir), n_sides=6, rotation=30, fill=0)

mask = mask.rotate(45, resample=Image.BICUBIC, center=(cx, cy))

# Soft shadow
shadow = mask.filter(ImageFilter.GaussianBlur(18 * SS)).point(lambda v: int(v * 0.28))
shadow_offset = Image.new("L", (N, N), 0)
shadow_offset.paste(shadow, (0, int(14 * u)))
bg = Image.composite(Image.new("RGB", (N, N), (120, 35, 10)), bg, shadow_offset)
bg = Image.composite(Image.new("RGB", (N, N), (255, 255, 255)), bg, mask)

bg.resize((S, S), Image.LANCZOS).convert("RGB").save(sys.argv[1], optimize=True)
