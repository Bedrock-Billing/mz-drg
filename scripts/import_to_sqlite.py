import sqlite3
import csv
import os
import glob
import json

# Define paths relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")
CSV_DIR = os.path.join(DATA_DIR, "csv")
DB_NAME = os.path.join(DATA_DIR, "msdrg.db")

def get_table_name(filename):
    # Convert filename like 'drgFormulas.csv' to 'drg_formulas'
    name = os.path.splitext(os.path.basename(filename))[0]
    return name

def infer_type(value):
    try:
        int(value)
        return "INTEGER"
    except ValueError:
        pass
    try:
        float(value)
        return "REAL"
    except ValueError:
        pass
    return "TEXT"

def import_csv_to_sqlite(csv_file, cursor):
    table_name = get_table_name(csv_file)
    print(f"Importing {csv_file} into table {table_name}...")

    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            print(f"Skipping empty file: {csv_file}")
            return

        # Let's peek at the first row
        first_row = None
        try:
            first_row = next(reader)
        except StopIteration:
            pass # Empty table with headers only

        columns_def = []
        for i, header in enumerate(headers):
            col_type = "TEXT"
            if first_row:
                col_type = infer_type(first_row[i])
            
            # Force 'value' to be TEXT (JSON)
            if header == 'value':
                col_type = "TEXT"
            
            columns_def.append(f'"{header}" {col_type}')

        create_stmt = f'CREATE TABLE IF NOT EXISTS "{table_name}" ({", ".join(columns_def)});'
        cursor.execute(create_stmt)

        # Prepare insert statement
        placeholders = ", ".join(["?"] * len(headers))
        insert_stmt = f'INSERT INTO "{table_name}" VALUES ({placeholders})'

        if first_row:
            cursor.execute(insert_stmt, first_row)
            
        # Insert the rest
        cursor.executemany(insert_stmt, reader)
        print(f"Imported {csv_file}.")

def main():
    if os.path.exists(DB_NAME):
        os.remove(DB_NAME)
    
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()

    csv_files = glob.glob(os.path.join(CSV_DIR, "*.csv"))
    for csv_file in csv_files:
        import_csv_to_sqlite(csv_file, cursor)

    conn.commit()
    conn.close()
    print(f"Database {DB_NAME} created successfully.")

if __name__ == "__main__":
    main()
