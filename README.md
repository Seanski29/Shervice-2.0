# Shervice: GT LANTIN Shuttle Service Management System

> **Upgrading manual fleet operations to an automated, data-driven system using analytics and modern web technologies.**

Shervice is a transport management system built to update the shuttle operations of GT LANTIN Shuttle Rental Services. It replaces manual tracking methods, whiteboards, and paper logs. The system manages over 70 vehicles and more than 12,000 weekly passenger trips for corporate clients, including EPSON, Bandai Namco, and NX Logistics.

By combining a web platform with a dual-engine backend, Shervice uses machine learning to predict vehicle maintenance, analyze route delays, and evaluate driver performance.

---

## System Architecture and Technology Stack

Shervice uses a structured design to clearly separate the user interface, system processes, and database management.

### 1. Presentation Layer (Frontend)

* **Authentication Hub:** React.js (18.3+) and Vite (5.0+) running on `localhost:3000`. Handles user sessions, secure logins, and role-based access.
* **Main Application Portal:** Flutter Web running on `localhost:8080`. Loads specific layouts based on the user's role (for example, `?role=admin`) passed from the React hub.
* **Styling and Layout:** Tailwind CSS (3.4) ensures the interface works well on mobile devices for drivers in the field.

### 2. Application Layer (Backend)

* **Primary Server:** Node.js (20.x) with Express.js (4.19) processes tasks, handles API requests, and manages data inputs like attendance and trip logs.
* **Real-Time Updates:** Socket.io (4.7) handles two-way communication, sending live updates and notifications to the Admin dashboard.
* **Analytics Engine:** Python Flask (3.0) runs as a separate service to host machine learning models and process complex calculations.

### 3. Data Layer

* **Database:** MySQL / PostgreSQL (16) stores driver records, operational logs, and maintenance histories.
* **Backend Service:** Supabase provides secure login features and real-time database updates.

---

## Machine Learning and Analytics

Shervice uses Scikit-learn (1.4) and Pandas (2.2) to turn daily logs into useful information for the business.

### 1. Driver Performance Classification (Random Forest)

This feature combines driver attendance records and passenger feedback to group driver performance into clear categories, such as Highly Reliable or Needs Improvement.

* **Evaluation Metrics:** Measured using Accuracy, Precision, Recall, and the F1-Score.

$$F_{1}=2\frac{precision\cdot recall}{precision+recall}$$

### 2. Predictive Maintenance (Multiple Linear Regression)

This model shifts fleet management from reacting to problems to preventing them. It calculates the relationship between past vehicle wear and future maintenance needs to avoid unexpected breakdowns.

$$y=\beta_0+\beta_1x_1+\beta_2x_2+...+\beta_nx_n+\epsilon$$

* **Evaluation Metrics:** Measured using Mean Absolute Error (MAE) and Root Mean Squared Error (RMSE).

### 3. Route Delay Analysis (K-Means Clustering)

This model groups similar route issues by analyzing distances, vehicle health, and arrival times. It helps dispatchers identify and fix common delays.

* **Optimization:** Minimizes the Within-Cluster Sum of Squares (WCSS).

$$J=\sum_{j=1}^{k}\sum_{i=1}^{n}\vert{}\vert{}x_i^{(j)}-c_j\vert{}\vert{}^2$$

---

## Core Features by User Role

* **Administrators and Staff:** Manage driver records, assign daily trips, log vehicle maintenance, and view the analytics dashboard for real-time performance tracking.
* **Drivers:** Use a mobile-friendly site to check assigned vehicles and schedules. Their attendance is recorded using biometric fingerprint scanners for daily time-in and time-out.
* **Officer-in-Charge (OIC):** Client representatives use a separate portal to submit shift schedules, provide passenger counts, and make specific trip requests.
* **Passengers:** Scan QR codes inside the vehicles to access a feedback form. They rate drivers on safety, attitude, and punctuality, which provides data for the machine learning models.

---

## Local Development and Setup

### Prerequisites

Make sure your computer has the following installed:

* Node.js v20+
* Flutter SDK
* Python 3.10+
* Supabase Account and CLI

### Running the System Locally

You need to run the backend and the frontend at the same time in separate terminal windows.

**Terminal 1: Python Backend**

```bash
cd shuttle-backend
# Activate your virtual environment (Windows example below)
.\Activate.ps1    
python app.py

```

**Terminal 2: Flutter Web Portal**

```bash
cd shervice_flutter
flutter run -d chrome --web-port 8080

```
