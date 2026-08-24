import sys
import os
from PIL import Image

def convert_image(image_path, format_type):
    # Load image and resize to 1080p
    img = Image.open(image_path)
    img = img.resize((1920, 1080), resample=Image.NEAREST)
    
    if format_type in ["RAW8", "RAW10", "RAW12"]:
        img = img.convert("L") # Grayscale
    elif format_type == "RAW24":
        img = img.convert("RGB") # Color
    
    # Get pixel data as flat list
    pixels = list(img.getdata())
    width, height = img.size
    
    out_lines = []
    
    if format_type == "RAW8":
        # 8-bit (0-255)
        for pixel in pixels:
            # pixel is just an int out of getdata() for grayscale "L"
            out_lines.append(f"{pixel:02X}")
                
    elif format_type == "RAW10":
        # Scale 8-bit to 10-bit: multiply by 4 (shift left by 2)
        for pixel in pixels:
            val10 = pixel << 2
            out_lines.append(f"{val10:03X}")
                
    elif format_type == "RAW12":
        # Scale 8-bit to 12-bit: multiply by 16 (shift left by 4)
        for pixel in pixels:
            val12 = pixel << 4
            out_lines.append(f"{val12:03X}")
                
    elif format_type == "RAW24":
        # 24-bit (R, G, B)
        for r, g, b in pixels:
            # Pack R, G, B into 24-bit hex
            val24 = (r << 16) | (g << 8) | b
            out_lines.append(f"{val24:06X}")
                
    else:
        print("Invalid format type!")
        return

    # Write to memory file compatible with Verilog $readmemh
    out_filename = os.path.join("mem_data", f"image_{format_type.lower()}.mem")
    with open(out_filename, "w") as f:
        f.write("\n".join(out_lines))
        
    print(f"Generated {out_filename} with {len(out_lines)} pixels formatted for {format_type}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Use the image provided by the user
        img_path = sys.argv[1]
        print(f"Using provided image: {img_path}")
    else:
        print("No image provided. Generating a solid red test_input.png")
        img_path = 'test_input.png'
        # Create a dummy test image
        Image.new('RGB', (1920, 1080), color = 'red').save(img_path)
    
    # Run conversion for all formats
    convert_image(img_path, 'RAW8')
    convert_image(img_path, 'RAW10')
    convert_image(img_path, 'RAW12')
    convert_image(img_path, 'RAW24')
