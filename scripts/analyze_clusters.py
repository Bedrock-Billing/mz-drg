import sqlite3
import json
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "..", "data", "msdrg.db")


def main():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Analyze Cluster Information
    print("Analyzing Cluster Information...")
    cursor.execute("SELECT key, value FROM clusterInformation")

    cluster_map = {}  # Z@ID -> Integer ID
    next_id = 1

    max_choices = 0
    max_codes_per_choice = 0

    for key, value_json in cursor:
        if key not in cluster_map:
            cluster_map[key] = next_id
            next_id += 1

        data = json.loads(value_json)
        choices = data.get("choices", [])
        if len(choices) > max_choices:
            max_choices = len(choices)

        for c in choices:
            codes = c.get("codes", [])
            if len(codes) > max_codes_per_choice:
                max_codes_per_choice = len(codes)

    print(f"Found {len(cluster_map)} unique clusters.")
    print(f"Max choices per cluster: {max_choices}")
    print(f"Max codes per choice: {max_codes_per_choice}")

    # Analyze Cluster IDs (Usage)
    print("\nAnalyzing Cluster IDs (Usage)...")
    cursor.execute("SELECT value FROM clusterIds")

    missing_clusters = set()

    for (value_json,) in cursor:
        cluster_list = json.loads(value_json)
        for c_id in cluster_list:
            if c_id not in cluster_map:
                missing_clusters.add(c_id)

    if missing_clusters:
        print(f"WARNING: {len(missing_clusters)} clusters referenced but not defined!")
        print(list(missing_clusters)[:5])
    else:
        print("All referenced clusters are defined.")

    conn.close()


if __name__ == "__main__":
    main()
