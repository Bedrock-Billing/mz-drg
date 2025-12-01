import ctypes
import json
import os

class MsdrgGrouper:
    def __init__(self, lib_path, data_dir):
        """
        Initialize the MS-DRG Grouper.
        
        :param lib_path: Path to the compiled shared library (libmsdrg.so/dll/dylib)
        :param data_dir: Path to the directory containing MS-DRG data files
        """
        if not os.path.exists(lib_path):
            raise FileNotFoundError(f"Library not found at {lib_path}")
        
        self.lib = ctypes.CDLL(lib_path)
        
        # --- Define C Function Signatures ---
        
        # Context
        self.lib.msdrg_context_init.argtypes = [ctypes.c_char_p]
        self.lib.msdrg_context_init.restype = ctypes.c_void_p
        
        self.lib.msdrg_context_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_context_free.restype = None
        
        # JSON API
        self.lib.msdrg_group_json.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.msdrg_group_json.restype = ctypes.c_void_p # Returns pointer (don't convert to bytes automatically)
        
        self.lib.msdrg_string_free.argtypes = [ctypes.c_void_p]
        self.lib.msdrg_string_free.restype = None

        # Initialize Context
        self.ctx = self.lib.msdrg_context_init(data_dir.encode('utf-8'))
        if not self.ctx:
            raise RuntimeError("Failed to initialize MS-DRG context. Check data directory.")

    def __del__(self):
        if hasattr(self, 'ctx') and self.ctx:
            self.lib.msdrg_context_free(self.ctx)
            self.ctx = None

    def group(self, claim_data):
        """
        Group a claim using the JSON API.
        
        :param claim_data: Dictionary containing claim data matching the InputClaim structure.
        :return: Dictionary containing the grouping result.
        """
        json_bytes = json.dumps(claim_data).encode('utf-8')
        
        # Call C API
        result_ptr = self.lib.msdrg_group_json(self.ctx, json_bytes)
        
        if not result_ptr:
            raise RuntimeError("Grouping failed (returned null)")
        
        try:
            # Read string from pointer
            result_json = ctypes.cast(result_ptr, ctypes.c_char_p).value.decode('utf-8')
            return json.loads(result_json)
        finally:
            # Free the string allocated by Zig
            self.lib.msdrg_string_free(result_ptr)

# Example Usage Helper
def create_claim(version, age, sex, discharge_status, pdx, sdx=None, procedures=None):
    claim = {
        "version": version,
        "age": age,
        "sex": sex, # 0=Male, 1=Female
        "discharge_status": discharge_status,
        "pdx": {"code": pdx},
        "sdx": [{"code": c} for c in (sdx or [])],
        "procedures": [{"code": c} for c in (procedures or [])]
    }
    return claim
