# 🚐 Shervice: GT LANTIN Shuttle Service Management System

> **Transforming manual fleet operations into a proactive, data-driven logistical ecosystem with predictive analytics and micro-frontend architecture.**

Shervice is a comprehensive transport management system engineered to modernize the shuttle fleet operations of GT LANTIN Shuttle Rental Services. Replacing legacy manual tracking methods, whiteboards, and paper logs, Shervice seamlessly coordinates over 70 vehicles and 12,000+ weekly passenger trips for multinational manufacturing clients, including EPSON, Bandai Namco, and NX Logistics.

By integrating a unified micro-frontend web architecture with a dual-engine backend, the platform utilizes advanced machine learning algorithms to forecast vehicle maintenance, analyze route delays, and objectively classify driver performance.

---

## System Architecture & Tech Stack

Shervice operates on a robust, multi-tier architecture, ensuring separation of concerns across user interfaces, system logic, and data management.

### 1. Presentation Layer (Micro-Frontend)

* **Authentication Hub:** React.js (18.3+) and Vite (5.0+) running on `localhost:3000`. Manages initial user sessions, secure login routing, and Role-Based Access Control (RBAC).
* **Main Application Portal:** Flutter Web running on `localhost:8080`. Dynamically renders role-specific layouts by reading URL query parameters (e.g., `?role=admin`) passed from the React hub via `dart:html`.
* **Styling & Responsiveness:** Tailwind CSS (3.4) guarantees a seamless, mobile-responsive experience for drivers operating in the field.

### 2. Application Layer (Dual-Engine Backend)

* **Primary Runtime:** Node.js (20.x) with Express.js (4.19) processes asynchronous tasks, handles RESTful API endpoints, and manages high-velocity data ingestion (attendance, trip logs).
* **Real-Time Engine:** Socket.io (4.7) drives bidirectional communication, delivering instant push notifications and live updates directly to the Admin dashboard.
* **Analytical Engine:** Python Flask (3.0) functions as a dedicated microservice, hosting the machine learning models and executing high-level computational tasks.

### 3. Data Layer

* **Relational Database:** MySQL / PostgreSQL (16) securely houses structured driver records, operational logs, and extensive maintenance histories.
* **Backend-as-a-Service:** Supabase enforces secure authentication protocols and provides real-time database listeners.

---

## Machine Learning & Predictive Analytics Pipeline

The core intelligence of Shervice transforms raw daily logs into actionable business intelligence utilizing Scikit-learn (1.4) and Pandas (2.2).

### 1. Driver Performance Classification (Random Forest)

Evaluates combined driver attendance logs and anonymous passenger evaluations to automatically classify overall driver performance into actionable categories (e.g., *Highly Reliable*, *Needs Improvement*).

* **Evaluation Metrics:** Validated using Accuracy, Precision, Recall, and the F1-Score.

$$F_{1}=2\frac{precision\cdot recall}{precision+recall}$$

### 2. Predictive Maintenance (Multiple Linear Regression)

Shifts fleet management from a reactive to a proactive state. Calculates the mathematical relationship between historical vehicle wear-and-tear and future required maintenance cycles to prevent unexpected breakdowns.

$$y=\beta_0+\beta_1x_1+\beta_2x_2+...+\beta_nx_n+\epsilon$$

* **Evaluation Metrics:** Validated using Mean Absolute Error (MAE) and Root Mean Squared Error (RMSE).

### 3. Route Delay Analysis (K-Means Clustering)

An unsupervised learning model that analyzes route distances, vehicle health, and actual arrival times. It automatically groups similar logistical bottlenecks, enabling dispatchers to visually identify and mitigate recurring delays.

* **Optimization:** Minimizes the Within-Cluster Sum of Squares (WCSS).

$$J=\sum_{j=1}^{k}\sum_{i=1}^{n}\vert{}\vert{}x_i^{(j)}-c_j\vert{}\vert{}^2$$

---

## Core Features by User Role

* **Administrators & Staff:** Oversee comprehensive driver records, manage daily vehicle dispatching, input maintenance logs, and access the React-based Performance Analytics Dashboard for real-time KPIs.
* **Drivers:** Access a mobile-responsive portal to verify vehicle assignments and shift schedules. Punctuality is tracked precisely via terminal biometric fingerprint scanners for daily time-in/time-out logging.
* **Officer-in-Charge (OIC):** Corporate client representatives utilize a dedicated portal to digitally submit shift requirements, input passenger counts, and formalize specific dispatch requests.
* **Passengers:** Scan in-vehicle QR codes to access an anonymous evaluation portal, rating drivers on safety, attitude, and punctuality to continuously feed the machine learning models.

---

## Local Development & Quick Start

### Prerequisites

Ensure your local environment meets the following requirements:

* [Node.js v20+](https://nodejs.org/)
* [Flutter SDK](https://flutter.dev/docs/get-started/install)
* [Python 3.10+](https://www.python.org/)
* [Supabase](https://supabase.com) Account & CLI

### Running the System Locally

You will need to run the analytical backend and the frontend portal concurrently in separate terminal windows.

**Terminal 1: Python Analytical Backend**

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
