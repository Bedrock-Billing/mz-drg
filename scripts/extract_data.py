import jpype
import jpype.imports
from jpype import JClass
import os
import csv
import sys
import json
from java.lang.reflect import Modifier

# Define paths
JAR_DIR = os.path.join(os.getcwd(), "jars")
DATA_DIR = os.path.join(os.getcwd(), "data")
jars = [
    "msdrg-binary-access-1.5.0.jar",
    "protobuf-java-3.22.2.jar",
    "msdrg-model-v2-2.11.0.jar",
    "gfc-base-api-3.4.9.jar",
    "gfc-base-factory-3.4.9.jar",
    "msdrg-core-43.1.0.0.jar",
]

classpath = [os.path.join(JAR_DIR, jar) for jar in jars]

print("Starting JVM with classpath:")
for cp in classpath:
    print(f"  {cp}")

# Start JVM
try:
    jpype.startJVM(classpath=classpath)
except OSError:
    print("JVM already started")


# Import classes
try:
    DataBlob = JClass("gov.agency.msdrg.access.DataBlob")
except Exception as e:
    print(f"Failed to load DataBlob class: {e}")
    sys.exit(1)


def get_private_field(instance, field_name):
    try:
        field = instance.getClass().getDeclaredField(field_name)
        field.setAccessible(True)
        return field.get(instance)
    except Exception as e:
        print(f"Error accessing field {field_name}: {e}")
        return None


def serialize_value(value):
    if value is None:
        return None

    # Handle JPype wrappers and Python types
    if isinstance(value, (str, int, float, bool)):
        return value

    # Check if it's a Java object
    if hasattr(value, "getClass"):
        cls = value.getClass()
        cls_name = str(cls.getName())

        # Handle Collections
        if (
            "java.util.List" in cls_name
            or "java.util.ArrayList" in cls_name
            or "java.util.LinkedList" in cls_name
        ):
            return [serialize_value(item) for item in value]

        if "java.util.Set" in cls_name or "java.util.HashSet" in cls_name:
            return [serialize_value(item) for item in value]

        if cls_name.startswith("java.lang."):
            return str(value)

        # Custom objects - use reflection to get fields
        fields = {}
        current_cls = cls
        while current_cls is not None and current_cls.getName() != "java.lang.Object":
            for f in current_cls.getDeclaredFields():
                if Modifier.isStatic(f.getModifiers()):
                    continue
                f.setAccessible(True)
                try:
                    val = f.get(value)
                    # Avoid infinite recursion if any
                    fields[str(f.getName())] = serialize_value(val)
                except Exception as e:
                    print(f"Error accessing field {f.getName()}: {e}")
                    pass
            current_cls = current_cls.getSuperclass()
        return fields

    return str(value)


def traverse_int_range_tree(node, results):
    if node is None:
        return

    # Access private fields of Node
    node_cls = node.getClass()

    def get_node_field(name):
        f = node_cls.getDeclaredField(name)
        f.setAccessible(True)
        return f.get(node)

    low = get_node_field("low")
    high = get_node_field("high")
    data = get_node_field("data")
    left = get_node_field("left")
    right = get_node_field("right")

    results.append((low, high, data))

    traverse_int_range_tree(left, results)
    traverse_int_range_tree(right, results)


def extract_int_range_map(blob, field_name, output_dir):
    print(f"Extracting {field_name}...")
    try:
        int_range_map = get_private_field(blob, field_name)
        if int_range_map is None:
            print(f"Field {field_name} is null or not found")
            return

        internal_container_field = int_range_map.getClass().getDeclaredField(
            "internalContainer"
        )
        internal_container_field.setAccessible(True)
        internal_container = internal_container_field.get(int_range_map)

        rows = []
        for entry in internal_container.entrySet():
            key = entry.getKey()
            tree = entry.getValue()

            root_field = tree.getClass().getDeclaredField("root")
            root_field.setAccessible(True)
            root = root_field.get(tree)

            ranges = []
            traverse_int_range_tree(root, ranges)

            for low, high, data in ranges:
                serialized_value = serialize_value(data)
                # If it's a list of strings (like in JSON), we might want to keep it as JSON string
                if isinstance(serialized_value, (list, dict)):
                    serialized_value = json.dumps(serialized_value)

                rows.append(
                    {
                        "key": str(key),
                        "version_start": low,
                        "version_end": high,
                        "value": serialized_value,
                    }
                )

        if rows:
            filename = os.path.join(output_dir, f"{field_name}.csv")
            with open(filename, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(
                    f, fieldnames=["key", "version_start", "version_end", "value"]
                )
                writer.writeheader()
                writer.writerows(rows)
            print(f"Saved {len(rows)} rows to {filename}")
        else:
            print(f"No data found for {field_name}")

    except Exception as e:
        print(f"Error extracting {field_name}: {e}")
        import traceback

        traceback.print_exc()


def extract_map(blob, field_name, output_dir):
    print(f"Extracting {field_name}...")
    try:
        data_map = get_private_field(blob, field_name)
        if data_map is None:
            print(f"Field {field_name} is null or not found")
            return

        rows = []
        for entry in data_map.entrySet():
            key = entry.getKey()
            value = entry.getValue()
            serialized_value = serialize_value(value)
            if isinstance(serialized_value, (list, dict)):
                serialized_value = json.dumps(serialized_value)

            rows.append({"key": str(key), "value": serialized_value})

        if rows:
            filename = os.path.join(output_dir, f"{field_name}.csv")
            with open(filename, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=["key", "value"])
                writer.writeheader()
                writer.writerows(rows)
            print(f"Saved {len(rows)} rows to {filename}")

    except Exception as e:
        print(f"Error extracting {field_name}: {e}")


def main():
    print("Getting DataBlob instance...")
    try:
        blob = DataBlob.getInstance()
        print("DataBlob instance retrieved.")
    except Exception as e:
        print(f"Error getting DataBlob instance: {e}")
        import traceback

        traceback.print_exc()
        return

    # Fields identified from DataBlob.java

    # IntRangeMap fields
    int_range_map_fields = [
        "diagnosisAll",
        "exclusionIds",
        "clusterInformation",
        "genderMdcs",
        "drgFormulas",
        "hacOperands",
        "hacFormulas",
        "procedureAttributes",
        "clusterIds",
        "baseDrgDescriptions",
        "drgDescriptions",
        "mdcDescriptions",
        "hacDescriptions",
    ]

    # Map fields
    map_fields = ["exclusionGroups", "dxPatterns", "prPatterns", "schemeIndex"]

    # Ensure output directory exists
    output_dir = os.path.join(DATA_DIR, "csv")
    os.makedirs(output_dir, exist_ok=True)

    for field in int_range_map_fields:
        extract_int_range_map(blob, field, output_dir)

    for field in map_fields:
        extract_map(blob, field, output_dir)

    print("Extraction complete.")


if __name__ == "__main__":
    main()
