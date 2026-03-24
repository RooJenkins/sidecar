#!/bin/bash
# Generate AppIcon.icns from an SVG
# Requires: sips (built into macOS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES="$PROJECT_DIR/Resources"
ICONSET="$RESOURCES/AppIcon.iconset"

mkdir -p "$ICONSET"

# Create a simple app icon as a PNG using Python (available on macOS)
python3 -c "
import struct, zlib, os

def create_png(width, height, filepath):
    \"\"\"Create a simple app icon PNG with a gradient background and document symbol.\"\"\"
    pixels = []
    for y in range(height):
        row = []
        for x in range(width):
            # Rounded rect with gradient background
            margin = width * 0.1
            corner = width * 0.18

            # Check if inside rounded rect
            ix = x - margin
            iy = y - margin
            iw = width - 2 * margin
            ih = height - 2 * margin

            inside = False
            if margin <= x <= width - margin and margin <= y <= height - margin:
                # Check corners
                if ix < corner and iy < corner:
                    inside = ((ix - corner)**2 + (iy - corner)**2) <= corner**2
                elif ix > iw - corner and iy < corner:
                    inside = ((ix - iw + corner)**2 + (iy - corner)**2) <= corner**2
                elif ix < corner and iy > ih - corner:
                    inside = ((ix - corner)**2 + (iy - ih + corner)**2) <= corner**2
                elif ix > iw - corner and iy > ih - corner:
                    inside = ((ix - iw + corner)**2 + (iy - ih + corner)**2) <= corner**2
                else:
                    inside = True

            if inside:
                # Blue-purple gradient
                t = y / height
                r = int(30 + 50 * t)
                g = int(100 + 40 * (1 - t))
                b = int(220 - 40 * t)
                a = 255

                # Draw a white document icon in center
                cx, cy = width / 2, height / 2
                dw, dh = width * 0.28, height * 0.36
                fold = width * 0.09
                dx = x - (cx - dw/2)
                dy = y - (cy - dh/2)

                in_doc = False
                if 0 <= dx <= dw and 0 <= dy <= dh:
                    # Main body minus fold corner
                    if dx <= dw - fold or dy >= fold:
                        in_doc = True
                    # Fold triangle
                    elif dx > dw - fold and dy < fold:
                        if dx - (dw - fold) + dy <= fold:
                            in_doc = True

                if in_doc:
                    # White document with slight transparency
                    r, g, b = 255, 255, 255

                    # Draw lines on the document
                    line_margin_x = dw * 0.15
                    line_top = dh * 0.3
                    if line_margin_x <= dx <= dw - line_margin_x:
                        for li in range(3):
                            ly = line_top + li * (dh * 0.15)
                            line_w = dw - 2 * line_margin_x
                            if li == 2:
                                line_w *= 0.6
                            if abs(dy - ly) < height * 0.012 and dx - line_margin_x <= line_w:
                                r, g, b = 160, 180, 210

                # Small magnifying glass overlay
                mgx = cx + dw * 0.3
                mgy = cy + dh * 0.3
                mgr = width * 0.1
                dist = ((x - mgx)**2 + (y - mgy)**2)**0.5

                if mgr - width*0.02 <= dist <= mgr + width*0.02:
                    r, g, b = 255, 255, 255
                elif dist < mgr - width*0.02:
                    # Lens tint
                    r = min(255, r + 30)
                    g = min(255, g + 30)
                    b = min(255, b + 30)

                # Handle of magnifying glass
                handle_start_x = mgx + mgr * 0.7
                handle_start_y = mgy + mgr * 0.7
                handle_len = width * 0.07
                for ht in range(int(handle_len)):
                    hx = handle_start_x + ht
                    hy = handle_start_y + ht
                    if abs(x - hx) < width*0.015 and abs(y - hy) < width*0.015:
                        r, g, b = 255, 255, 255

                row.extend([r, g, b, a])
            else:
                row.extend([0, 0, 0, 0])
        pixels.append(bytes([0] + row))  # filter byte + pixel data

    raw = b''.join(pixels)

    def make_chunk(chunk_type, data):
        chunk = chunk_type + data
        return struct.pack('>I', len(data)) + chunk + struct.pack('>I', zlib.crc32(chunk) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)

    png = b'\\x89PNG\\r\\n\\x1a\\n'
    png += make_chunk(b'IHDR', ihdr)
    png += make_chunk(b'IDAT', zlib.compress(raw))
    png += make_chunk(b'IEND', b'')

    with open(filepath, 'wb') as f:
        f.write(png)

# Generate the base 1024x1024 icon
create_png(1024, 1024, '$ICONSET/icon_512x512@2x.png')
print('Generated 1024x1024 base icon')
"

# Generate all required sizes using sips
cd "$ICONSET"
BASE="icon_512x512@2x.png"

for size in 16 32 64 128 256 512; do
    sips -z $size $size "$BASE" --out "icon_${size}x${size}.png" > /dev/null
done
# Retina versions
sips -z 32 32 "$BASE" --out "icon_16x16@2x.png" > /dev/null
sips -z 64 64 "$BASE" --out "icon_32x32@2x.png" > /dev/null
sips -z 256 256 "$BASE" --out "icon_128x128@2x.png" > /dev/null
sips -z 512 512 "$BASE" --out "icon_256x256@2x.png" > /dev/null

# Remove the 64x64 (not a valid iconset size)
rm -f "icon_64x64.png"

# Convert to .icns
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
rm -rf "$ICONSET"

echo "Generated AppIcon.icns at $RESOURCES/AppIcon.icns"
