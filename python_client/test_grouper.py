import os
from msdrg import MsdrgGrouper, create_claim

def main():
    # Paths relative to this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    
    lib_path = os.path.join(root_dir, "zig_src", "zig-out", "lib", "libmsdrg.so")
    data_dir = os.path.join(root_dir, "data", "bin")
    
    print(f"Library Path: {lib_path}")
    print(f"Data Dir: {data_dir}")
    
    if not os.path.exists(lib_path):
        print("Error: Library file not found. Did you run 'zig build'?")
        return

    try:
        grouper = MsdrgGrouper(lib_path, data_dir)
        
        # Create a test claim
        # Version 40 (v400) - Adjust based on available data versions
        # Age 65, Male, Discharged to Home (01)
        # PDX: I10 (Hypertension) - Just a guess at a valid code
        claim = create_claim(
            version=400, 
            age=65, 
            sex=0, 
            discharge_status=1, 
            pdx="A000" 
        )
        
        print("\nSending Claim:")
        print(claim)
        
        result = grouper.group(claim)
        
        print("\nGrouping Result:")
        import json
        print(json.dumps(result, indent=2))
        
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
