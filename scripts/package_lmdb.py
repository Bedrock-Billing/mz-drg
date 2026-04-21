import lmdb
import os
import sys
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def package_to_lmdb(bin_dir: Path, output_path: Path):
    """
    Consolidates all .bin files in bin_dir into a single LMDB database.
    """
    if not bin_dir.exists():
        logger.error(f"Binary directory not found: {bin_dir}")
        sys.exit(1)

    # Estimate map size - current total is ~14MB, use 100MB for growth
    map_size = 100 * 1024 * 1024
    
    logger.info(f"Creating LMDB at {output_path}...")
    
    # LMDB environment
    # subdir=False means output_path is the filename, not a directory
    try:
        env = lmdb.open(str(output_path), map_size=map_size, subdir=False)
    except Exception as e:
        logger.error(f"Failed to open LMDB environment: {e}")
        sys.exit(1)
    
    # Files not loaded by the Zig reader — skip to avoid bloating the LMDB.
    # - hac_operands: superseded by diagnosis scheme hac_operand_pattern → dx_patterns
    # - base_drg_descriptions: no corresponding Zig reader
    EXCLUDED_KEYS = {"hac_operands", "base_drg_descriptions"}

    count = 0
    with env.begin(write=True) as txn:
        for bin_file in sorted(bin_dir.glob("*.bin")):
            key = bin_file.stem
            if key in EXCLUDED_KEYS:
                logger.info(f"  Skipping {bin_file.name} (unused by Zig reader)")
                continue
            logger.info(f"  Packing {bin_file.name} as key '{key}'...")
            try:
                with open(bin_file, "rb") as f:
                    data = f.read()
                
                # Pad data to 8-byte boundary
                padding_needed = (8 - (len(data) % 8)) % 8
                if padding_needed > 0:
                    data += b'\x00' * padding_needed
                    
                # Pad key to 8-byte boundary to ensure values are 8-byte aligned in LMDB
                key_bytes = key.encode("utf-8")
                padding_needed_key = (8 - (len(key_bytes) % 8)) % 8
                if padding_needed_key > 0:
                    key_bytes += b'\x00' * padding_needed_key
                    
                txn.put(key_bytes, data)
                count += 1
            except Exception as e:
                logger.error(f"  Failed to pack {bin_file}: {e}")
                sys.exit(1)
    
    logger.info(f"Successfully packed {count} files into {output_path}")
    env.close()

if __name__ == "__main__":
    # Get project root (parent of scripts directory)
    project_root = Path(__file__).parent.parent.absolute()
    
    bin_dir = project_root / "data" / "bin"
    output_path = project_root / "data" / "msdrg.mdb"
    
    package_to_lmdb(bin_dir, output_path)
