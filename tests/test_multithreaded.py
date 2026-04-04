"""
Multithreaded MS-DRG grouper example.

Demonstrates thread-safe concurrent grouping using a single MsdrgGrouper
instance shared across multiple Python threads. The Zig grouper context
is immutable after initialization and safe for concurrent access.

Usage:
    python tests/test_multithreaded.py
    python tests/test_multithreaded.py --threads 8 --claims 5000
"""

import json
import time
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed

from msdrg import MsdrgGrouper


def worker(grouper: MsdrgGrouper, claims: list[dict], results: list, start: int):
    """Process a slice of claims and store (drg, mdc) tuples in results."""
    for i, claim in enumerate(claims):
        r = grouper.group(claim)
        results[start + i] = (r["final_drg"], r["final_mdc"])


def run_sequential(grouper: MsdrgGrouper, claims: list[dict]) -> list:
    """Baseline: single-threaded processing."""
    results = [None] * len(claims)
    start = time.perf_counter()
    for i, claim in enumerate(claims):
        r = grouper.group(claim)
        results[i] = (r["final_drg"], r["final_mdc"])
    elapsed = time.perf_counter() - start
    return results, elapsed


def run_threaded(grouper: MsdrgGrouper, claims: list[dict], num_threads: int) -> list:
    """Multi-threaded processing using ThreadPoolExecutor."""
    results = [None] * len(claims)
    chunk_size = len(claims) // num_threads

    start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = []
        for t in range(num_threads):
            chunk_start = t * chunk_size
            chunk_end = chunk_start + chunk_size if t < num_threads - 1 else len(claims)
            chunk = claims[chunk_start:chunk_end]
            futures.append(
                executor.submit(worker, grouper, chunk, results, chunk_start)
            )
        for f in as_completed(futures):
            f.result()  # propagate exceptions
    elapsed = time.perf_counter() - start
    return results, elapsed


def run_fine_grained(
    grouper: MsdrgGrouper, claims: list[dict], num_threads: int
) -> list:
    """Fine-grained: submit each claim as a separate task."""
    results = [None] * len(claims)

    def process_one(idx: int, claim: dict):
        r = grouper.group(claim)
        results[idx] = (r["final_drg"], r["final_mdc"])

    start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = {executor.submit(process_one, i, c): i for i, c in enumerate(claims)}
        for f in as_completed(futures):
            f.result()
    elapsed = time.perf_counter() - start
    return results, elapsed


def main():
    parser = argparse.ArgumentParser(description="Multithreaded MS-DRG grouper test")
    parser.add_argument(
        "--claims", type=int, default=1000, help="Number of claims to process"
    )
    parser.add_argument("--threads", type=int, default=4, help="Number of threads")
    parser.add_argument(
        "--file", type=str, default="tests/test_claims.json", help="Claims file"
    )
    parser.add_argument(
        "--all-modes", action="store_true", help="Run all modes for comparison"
    )
    args = parser.parse_args()

    print(f"Loading {args.claims} claims from {args.file}...")
    with open(args.file) as f:
        all_claims = json.load(f)
    claims = all_claims[: args.claims]
    print(f"Loaded {len(claims)} claims\n")

    with MsdrgGrouper() as grouper:
        # Sequential baseline
        print("=== Sequential (single thread) ===")
        seq_results, seq_time = run_sequential(grouper, claims)
        seq_rps = len(claims) / seq_time
        print(f"  {seq_time:.3f}s — {seq_rps:,.0f} claims/sec\n")

        # Chunked threading
        print(f"=== Threaded ({args.threads} threads, chunked) ===")
        thr_results, thr_time = run_threaded(grouper, claims, args.threads)
        thr_rps = len(claims) / thr_time
        print(f"  {thr_time:.3f}s — {thr_rps:,.0f} claims/sec")
        print(f"  Speedup: {thr_rps / seq_rps:.2f}x vs sequential\n")

        if args.all_modes:
            # Fine-grained threading
            print(f"=== Threaded ({args.threads} threads, fine-grained) ===")
            fg_results, fg_time = run_fine_grained(grouper, claims, args.threads)
            fg_rps = len(claims) / fg_time
            print(f"  {fg_time:.3f}s — {fg_rps:,.0f} claims/sec")
            print(f"  Speedup: {fg_rps / seq_rps:.2f}x vs sequential\n")

        # Verify results match
        print("=== Verification ===")
        if args.all_modes:
            matches = sum(1 for a, b in zip(seq_results, fg_results) if a == b)
            print(f"  Sequential vs fine-grained: {matches}/{len(claims)} match")
        else:
            matches = sum(1 for a, b in zip(seq_results, thr_results) if a == b)
            print(f"  Sequential vs threaded: {matches}/{len(claims)} match")

        if matches == len(claims):
            print("  OK — all results identical across threads")
        else:
            print("  WARNING — some results differ!")

    print("\nDone.")


if __name__ == "__main__":
    main()
