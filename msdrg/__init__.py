"""
msdrg - MS-DRG Grouper Python bindings

A high-performance MS-DRG (Medicare Severity Diagnosis Related Groups)
grouper implemented in Zig with Python bindings via ctypes.

Usage:
    import msdrg

    grouper = msdrg.MsdrgGrouper()
    result = grouper.group({
        "version": 431,
        "age": 65,
        "sex": 0,
        "discharge_status": 1,
        "pdx": {"code": "I5020"},
        "sdx": [{"code": "E1165"}],
        "procedures": []
    })
    print(result["final_drg"])
"""

from msdrg.grouper import MsdrgGrouper, create_claim

__version__ = "0.1.1"
__all__ = ["MsdrgGrouper", "create_claim"]
