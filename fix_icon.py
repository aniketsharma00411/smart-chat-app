from PIL import Image

def remove_black_and_checkerboard(input_path, output_path):
    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()
    
    newData = []
    for item in datas:
        # Check for black (background) 
        # Adjust threshold as needed. 
        # Vayu icon is likely blue on black.
        # If the pixel is very dark, make it transparent.
        if item[0] < 30 and item[1] < 30 and item[2] < 30:
             newData.append((0, 0, 0, 0))
        else:
             newData.append(item)
             
    img.putdata(newData)
    img.save(output_path, "PNG")
    print(f"Saved to {output_path}")

# Source: Original Vayu Icon (Blue on Black)
source_path = "/Users/sumedhakoranga/.gemini/antigravity/brain/77a1d7b5-cbcb-42d1-bf9c-810adcb6b3ea/vayu_icon_1770542889434.png"
dest_path = "assets/branding/app_icon.png"

remove_black_and_checkerboard(source_path, dest_path)
