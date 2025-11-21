---
title: "Batch Convert Hitachi TIFs to DM4"
collection: scripts
type: "Python DMscript"
permalink: /scripts/imagej-particle-analysis/
excerpt: 'Done'
date: 2025-11-21
---

If you work with Hitachi SEM/STEM systems (e.g., HF5000), the export format is often a `.tif` image paired with a `.txt` file containing acquisition parameters. Opening the TIF directly in Gatan DigitalMicrograph (GMS) yields an uncalibrated image without metadata and often includes a "burned-in" info bar that interferes with FFT or measurements.

This script automates conversion to `.dm4`, applies calibration, writes metadata tags, and optionally crops the image to a square to remove info bars.

## Key features

- Batch processing: convert all `.tif` files in a folder to `.dm4`.
- Auto-calibration: read `PixelSize` from the companion `.txt` and set X/Y scale and units (nm).
- Metadata import: parse acquisition parameters (Voltage, Magnification, Stage Position, …) and save under `Private:Hitachi_Metadata`.
- Smart cropping: optional `CROP_TO_SQUARE` removes rectangular footer/data bar and produces a square image for analysis.
- Robust: handles missing metadata gracefully and reports progress.

## Usage

1. Prepare data: put `.tif` images and their corresponding `.txt` metadata files in the same folder.
2. Open the script in GMS (Python scripting interface) and set `TARGET_FOLDER` to your data path.
3. Configure `CROP_TO_SQUARE = True` to remove the info bar, or `False` to keep original size.
4. Run the script — converted `.dm4` files will be saved next to the originals.

## Configuration notes

- TARGET_FOLDER: full path string to the folder containing `.tif` files.
- CROP_TO_SQUARE: boolean, default `True`.
- The script writes tags under `Private:Hitachi_Metadata`. Open the Tag browser (Ctrl+K) to inspect.

## Script Code
```python
# -*- coding: utf-8 -*-
import DigitalMicrograph as DM
import os
import glob

# ==============================================================================
# [CONFIGURATION]
# ==============================================================================


# [IMPORTANT] Please paste your folder path inside the quotes below
TARGET_FOLDER = r"YOUR_DATA_PATH"


# True = Crop extra info bar (keep top-left square). 
# False = Keep original size.
CROP_TO_SQUARE = True 

# ==============================================================================

def parse_hitachi_metadata(txt_path):
    """Parses the Hitachi txt metadata file."""
    metadata = {}
    try:
        if os.path.exists(txt_path):
            with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.strip()
                    if line and '=' in line:
                        parts = line.split('=', 1)
                        if len(parts) == 2:
                            metadata[parts[0].strip()] = parts[1].strip()
    except Exception as e:
        print(f"Error reading metadata: {txt_path}, Error: {e}")
    return metadata

def crop_image_to_square(img):
    """
    Checks if image is rectangular. If so, crops to the largest square.
    Returns the new cropped image object. Deletes the old one.
    """
    try:
        cols = img.GetDimensionSize(0) # Width (X)
        rows = img.GetDimensionSize(1) # Height (Y)
        
        # If already square, do nothing
        if cols == rows:
            return img
            
        # Determine square size (min side)
        size = min(cols, rows)

        # Get data as Numpy array
        data = img.GetNumArray()
        
        # [CRITICAL] Slice AND Copy
        # Must use .copy() to create a contiguous array for DM
        cropped_data = data[:size, :size].copy()
        
        # Create NEW image from cropped data
        new_img = DM.CreateImage(cropped_data)
        
        # [MODIFIED] Use DM.DeleteImage instead of img.Close()
        DM.DeleteImage(img)
        
        return new_img
        
    except Exception as e:
        print(f"   [Warning] Crop failed: {e}. Keeping original size.")
        return img

def apply_calibration_and_tags(img, metadata):
    """Applies metadata to DM image."""
    # 1. Calibration (Scale)
    if 'PixelSize' in metadata:
        try:
            pixel_size = float(metadata['PixelSize'])
            
            # [MODIFIED] Using SetDimensionUnitInfo as requested
            
            # Y axis (1)
            img.SetDimensionScale(1, pixel_size)
            img.SetDimensionUnitInfo(1, 'nm', 1)
            
            # X axis (0)
            img.SetDimensionScale(0, pixel_size)
            img.SetDimensionUnitInfo(0, 'nm', 1)
            
        except ValueError:
            pass
        except AttributeError:
             pass

    # 2. Write Tags (Private:Hitachi_Metadata)
    try:
        tag_group = img.GetTagGroup()
    except:
        return

    base_tag_path = "Private:Hitachi_Metadata"
    
    for key, value in metadata.items():
        safe_key = key.replace(" ", "_").replace("/", "_").replace(":", "")
        try:
            tag_group.SetTagAsString(f"{base_tag_path}:{safe_key}", value)
        except:
            pass
        
    # 3. Standard Info
    if 'Magnification' in metadata:
        try:
            mag = float(metadata['Magnification'])
            tag_group.SetTagAsFloat("Microscope Info:Indicated Magnification", mag)
        except: pass
        
    if 'Accelerating voltage' in metadata:
        try:
            volts = float(metadata['Accelerating voltage'])
            tag_group.SetTagAsFloat("Microscope Info:Voltage", volts)
        except: pass

def batch_convert_main():
    print("Starting batch conversion...")
    print(f"Target Folder: {TARGET_FOLDER}")
    
    if not os.path.exists(TARGET_FOLDER):
        print("Error: Invalid folder path.")
        return

    tif_files = glob.glob(os.path.join(TARGET_FOLDER, "*.tif"))
    
    if not tif_files:
        print("No .tif files found.")
        return

    print(f"Found {len(tif_files)} TIF files. Processing...")

    count = 0
    for tif_path in tif_files:
        txt_path = os.path.splitext(tif_path)[0] + ".txt"
        metadata = parse_hitachi_metadata(txt_path)

        try:
            # 1. Open Image
            img = DM.OpenImage(tif_path)
            
            if img.IsValid():
                # 2. Crop (Optional)
                if CROP_TO_SQUARE:
                    # This function now uses DM.DeleteImage internally for the old image
                    img = crop_image_to_square(img)

                # 3. Apply info
                apply_calibration_and_tags(img, metadata)
                
                # 4. Save as .dm4
                save_path = os.path.splitext(tif_path)[0] + ".dm4"
                img.SaveAsGatan(save_path)
                
                # 5. Close final image
                # [MODIFIED] Use global DeleteImage
                DM.DeleteImage(img)
                
                count += 1
                if count % 10 == 0:
                    print(f"Processed {count}/{len(tif_files)}...")
            else:
                print(f"Skipping invalid image: {os.path.basename(tif_path)}")
                
        except Exception as e:
            print(f"Error processing {os.path.basename(tif_path)}: {e}")

    print("---")
    print(f"Success! Converted {count} files.")
    try:
        DM.OkDialog(f"Success! Converted {count} files.\nFolder: {TARGET_FOLDER}")
    except:
        pass

if __name__ == "__main__":
    batch_convert_main()
```