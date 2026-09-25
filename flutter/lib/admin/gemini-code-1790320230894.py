import pandas as pd
from datetime import datetime, timedelta
import random
import calendar

# --- 1. Your Exact Live Database Drivers ---
DRIVER_DATA = {
    24: "Sean Del Rosario", 33: "Lemon Laurel Mendoza", 40: "Ralph Emmerson Lucero",
    41: "Gian Carlo Diaz", 42: "Jet Gundamn Agasino", 43: "Jarell Cyrus Paulite",
    44: "Howies Dela Cruz", 45: "Janella Maxine Lantin", 81: "Ance Villar",
    82: "Jeff Jeffrey", 83: "John Doe", 84: "Jane Doe",
    85: "Steph Stephen", 86: "Al James", 87: "Ant Anthony",
    88: "Marc Marcus", 89: "Mark Markus", 90: "Laurenz Kyle",
    91: "James Patrick", 92: "Peter Retep", 93: "Steve Steven",
    94: "Kim Stars", 95: "Hans Sel", 96: "Bin Go",
    97: "Crin Kles", 98: "Fudge Bar", 99: "Koko Krunch",
    100: "Kris P Kreme", 101: "Hol O Knight", 102: "Stewie Griffin",
    103: "Reb Bisco", 104: "Prin Gels", 105: "Si Xeven",
    106: "Yi Longma", 107: "Justine Kyle", 108: "Jack E Chan",
    109: "Bruce Lee", 110: "Ben Ten", 111: "Vil Gax",
    112: "Parker Peter", 113: "Clark Cant", 114: "Berry Allen"
}

drivers = [{'driver_id': d_id, 'full_name': name} for d_id, name in DRIVER_DATA.items()]

# --- 2. Setup Machine Learning Tiers ---
random.shuffle(drivers)
elite_drivers = [d['driver_id'] for d in drivers[:8]]
tardiness_risks = [d['driver_id'] for d in drivers[8:16]]

# --- 3. Generate Pay Periods (Jan - Sept 2026) ---
pay_periods = []
for month in range(1, 10):
    last_day = calendar.monthrange(2026, month)[1]
    pay_periods.append((datetime(2026, month, 1), datetime(2026, month, 15)))
    pay_periods.append((datetime(2026, month, 16), datetime(2026, month, last_day)))

def calc_work_time(t_in, t_out):
    fmt = '%I:%M %p'
    tdelta = datetime.strptime(t_out, fmt) - datetime.strptime(t_in, fmt)
    hours, remainder = divmod(tdelta.seconds, 3600)
    minutes, _ = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}"

rows = []

# --- 4. Build ZKTeco Report Structure ---
for p_start, p_end in pay_periods:
    p_label = f"{p_start.strftime('%Y-%m-%d')}-{p_end.strftime('%Y-%m-%d')}"
    
    for driver in drivers:
        d_id = driver['driver_id']
        d_name = driver['full_name']
        
        rows.append(['Timecard Report ', '', '', '', '', '', ''])
        rows.append(['', '', '', '', '', '', ''])
        rows.append(['Pay Period', '', '', p_label, '', '', ''])
        rows.append(['Employee', '', '', f"{d_name} ({d_id})", '', '', ''])
        rows.append(['Date', '', 'IN', 'OUT', 'Work Time', 'Daily Total', 'Note'])
        
        curr_date = p_start
        while curr_date <= p_end:
            if curr_date.weekday() == 6:  # Skip Sundays
                curr_date += timedelta(days=1)
                continue
                
            day_str = curr_date.strftime('%a').upper()
            date_str = curr_date.strftime('%Y-%m-%d')
            
            # --- SHIFT LOGIC (Strict AM/PM strings for Flutter parser) ---
            status = "Present"
            m_in = "03:00 AM"
            m_out = "07:00 AM"
            a_in = "03:00 PM"
            a_out = "07:00 PM"
            
            # Elite drivers occasionally get OVERTIME past 7 AM and 7 PM
            if d_id in elite_drivers and random.random() < 0.3:
                m_out = "08:00 AM"
                a_out = "08:00 PM"
                
            m_note = "Morning completed"
            a_note = "Afternoon completed"
            
            # Tardiness Behavior
            if d_id in tardiness_risks:
                if random.random() < 0.2:
                    status = "Absent"
                elif random.random() < 0.6:
                    m_in = f"03:{random.randint(15, 59):02d} AM"
                    m_note = "Late morning arrival"
            elif d_id not in elite_drivers:
                if random.random() < 0.05:
                    status = "Half Day"
                elif random.random() < 0.1:
                    m_in = f"03:{random.randint(5, 14):02d} AM"
                    m_note = "Minor late arrival"
            
            # Append rows based on biometric 4-punch style
            if status == "Absent":
                rows.append([day_str, date_str, '', '', '', '', 'Absent'])
                rows.append(['', '', '', '', '', '', ''])
            
            elif status == "Half Day":
                m_work = calc_work_time(m_in, m_out)
                rows.append([day_str, date_str, m_in, m_out, m_work, m_work, m_note])
                rows.append(['', '', '', '', '', '', 'Half day absent'])
            
            else:
                m_work = calc_work_time(m_in, m_out)
                a_work = calc_work_time(a_in, a_out)
                rows.append([day_str, date_str, m_in, m_out, m_work, m_work, m_note])
                rows.append(['', '', a_in, a_out, a_work, a_work, a_note])
                
            curr_date += timedelta(days=1)

# --- 5. Export to CSV ---
df = pd.DataFrame(rows)
df.to_csv('Biometric_Import.csv', index=False, header=False)
print("✅ Success! Generated Biometric_Import.csv with verified driver records.")