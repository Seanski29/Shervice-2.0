import random
import calendar
from datetime import datetime, timedelta

# --- 1. System Constants ---
VEHICLE_IDS = [
    15, 16, 17, 18, 19, 20, 21, 22, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 
    39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 53, 55, 100, 101, 102, 103, 104, 105, 
    106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 
    121, 122, 123, 124, 125, 126, 127, 128, 129
]
USER_ID = "10e48177-df4f-4e96-995e-de4b6a527020"
CATEGORIES = ['General', 'Engine', 'Exterior', 'Interior', 'Electrical', 'Tires/Wheels']

inserts = []

def format_val(val):
    """Wraps strings in quotes, leaves booleans/numbers alone, and outputs NULL for None."""
    if val is None:
        return "NULL"
    elif isinstance(val, bool):
        return "true" if val else "false"
    elif isinstance(val, int):
        return str(val)
    else:
        return f"'{val}'"

# --- 2. Generate Monthly Preventive Maintenance (Jan - Sep) ---
for v_id in VEHICLE_IDS:
    # Randomize starting category so vehicles aren't all getting the same check at once
    start_cat_idx = random.randint(0, 5) 
    for month in range(1, 10):
        days_in_month = calendar.monthrange(2026, month)[1]
        day = random.randint(1, days_in_month)
        date_str = f"2026-{month:02d}-{day:02d}"
        
        cat = CATEGORIES[(start_cat_idx + month) % 6]
        desc = f"Monthly {cat.lower()} inspection based on active trip operations"
        
        # Columns: repair_date, description, vehicle_id, user_id, category, incident_date, incident_time, repair_time, is_resolved, target_date, maintenance_type
        inserts.append(
            f"(NULL, '{desc}', {v_id}, '{USER_ID}', '{cat}', '{date_str}', '08:00:00', NULL, true, NULL, 'maintenance')"
        )

# --- 3. Generate Resolved Repairs (Jan - Aug) ---
for v_id in VEHICLE_IDS:
    # 1 to 3 random repairs per vehicle over 8 months
    num_repairs = random.randint(1, 3)
    for _ in range(num_repairs):
        month = random.randint(1, 8)
        day = random.randint(1, 28)
        inc_date = datetime(2026, month, day)
        rep_date = inc_date + timedelta(days=random.randint(0, 3))
        
        cat = random.choice(CATEGORIES)
        i_date_str = inc_date.strftime('%Y-%m-%d')
        r_date_str = rep_date.strftime('%Y-%m-%d')
        i_time = f"{random.randint(6, 11):02d}:00:00"
        r_time = f"{random.randint(13, 18):02d}:30:00"
        desc = "Vehicle repair recorded after accumulated operating workload"
        
        inserts.append(
            f"('{r_date_str}', '{desc}', {v_id}, '{USER_ID}', '{cat}', '{i_date_str}', '{i_time}', '{r_time}', true, NULL, 'repair')"
        )

# --- 4. Generate Unresolved "Open" Repairs (Late September) ---
# Pick 15 random vehicles to have pending issues at the end of the data period
open_vehicles = random.sample(VEHICLE_IDS, 15)
for v_id in open_vehicles:
    day = random.randint(15, 30)
    date_str = f"2026-09-{day:02d}"
    cat = random.choice(CATEGORIES)
    i_time = f"{random.randint(7, 14):02d}:00:00"
    desc = "Open repair issue requiring staff attention"
    
    inserts.append(
        f"(NULL, '{desc}', {v_id}, '{USER_ID}', '{cat}', '{date_str}', '{i_time}', NULL, false, NULL, 'repair')"
    )

# --- 5. Export to SQL File ---
with open('06_predictive_maintenance.sql', 'w', encoding='utf-8') as f:
    f.write("-- 1. Truncate existing table and reset IDs\n")
    f.write("TRUNCATE TABLE public.maintenance_log RESTART IDENTITY CASCADE;\n\n")
    
    f.write("-- 2. Insert separated maintenance and repair logs\n")
    columns = "(repair_date, description, vehicle_id, user_id, category, incident_date, incident_time, repair_time, is_resolved, target_date, maintenance_type)"
    batch_size = 200
    
    for i in range(0, len(inserts), batch_size):
        f.write(f"INSERT INTO public.maintenance_log {columns} VALUES \n")
        f.write(",\n".join(inserts[i:i+batch_size]) + ";\n\n")

print(f"✅ Success! Created 06_predictive_maintenance.sql with {len(inserts)} properly typed logs.")