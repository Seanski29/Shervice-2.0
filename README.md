# Shervice: GT LANTIN Shuttle Service Management System

> **Upgrading manual fleet operations to an automated, data-driven ecosystem using machine learning and modern web technologies.**

Shervice is an enterprise-grade transport management system engineered to modernize the shuttle operations of GT LANTIN Shuttle Rental Services. Replacing legacy tracking methods, whiteboards, and paper logs, the platform seamlessly coordinates over 70 vehicles and 12,000+ weekly passenger trips for top-tier corporate clients including EPSON, Bandai Namco, and NX Logistics.

By uniting a cross-platform web interface with a dual-engine backend, Shervice leverages machine learning to predict vehicle maintenance, analyze route delays, and continuously evaluate driver performance.

---

## System Architecture and Technology Stack

Shervice utilizes a modular architecture to strictly separate the user interface, background processing, and database management, ensuring scalability and maintainability.

### 1. Presentation Layer (Frontend)

* **Unified Web Portal:** Built entirely in Flutter Web, running on `Railway`. Manages the complete user journey from secure authentication sessions , role-based application layouts (Admin and Staff).
* **Responsive Enterprise UI:** Utilizes custom Flutter themes (`EnterpriseColors`, `EnterpriseEmptyState`) and responsive `LayoutBuilder` constraints to ensure the interface adapts flawlessly from desktop admin monitors to mobile devices used by drivers in the field.

### 2. Application Layer (Backend)

* **Primary Server:** Node.js (20.x) with Express.js (4.19) manages core business logic, API requests, and data ingestion (attendance and trip logs).
* **Real-Time Updates:** Socket.io (4.7) drives bidirectional communication, pushing live operational updates and alerts directly to the Admin dashboard.
* **Analytics Engine:** Python Flask (3.0) operates as a dedicated microservice to host the machine learning models and execute heavy computational analytics.

### 3. Data Layer

* **Database:** MySQL / PostgreSQL (16) serves as the primary relational store for driver records, historical operational logs, and maintenance tracking.
* **Backend-as-a-Service:** Supabase provides secure authentication infrastructure and real-time database synchronization.

---

## Machine Learning and Analytics

Shervice integrates Scikit-learn (1.4) and Pandas (2.2) to transform raw daily logs into actionable operational intelligence.

### 1. Driver Performance Classification (Random Forest)

This model synthesizes biometric attendance records with live passenger feedback to autonomously categorize driver performance into actionable tiers (e.g., Highly Reliable, Needs Improvement).

* **Evaluation Metrics:** Validated using Accuracy, Precision, Recall, and the F1-Score.

$$F_{1}=2\frac{precision\cdot recall}{precision+recall}$$

### 2. Predictive Maintenance (Multiple Linear Regression)

Transitioning the fleet from reactive repairs to preventative care, this model calculates the correlation between historical vehicle wear metrics and future servicing requirements to mitigate unexpected downtime.

$$y=\beta_0+\beta_1x_1+\beta_2x_2+...+\beta_nx_n+\epsilon$$

* **Evaluation Metrics:** Validated using Mean Absolute Error (MAE) and Root Mean Squared Error (RMSE).

### 3. Route Delay Analysis (K-Means Clustering)

This spatial model groups analogous routing bottlenecks by evaluating transit distances, vehicle health metrics, and historical arrival variances, allowing dispatchers to systematically resolve common delays.

* **Optimization Target:** Minimizes the Within-Cluster Sum of Squares (WCSS).

$$J=\sum_{j=1}^{k}\sum_{i=1}^{n}\Vert{}x_i^{(j)}-c_j\Vert{}^2$$

---

## Core Features by User Role

* **Administrators and Dispatch Staff:** Maintain driver registries, assign daily trip schedules, log vehicle maintenance events, and monitor the live analytics dashboard for real-time fleet performance.
* **Drivers:** Access a mobile-optimized web portal to review assigned vehicles and routing schedules. On-site attendance is securely logged via biometric fingerprint scanners for precise time-in/time-out tracking.
* **Officer-in-Charge (OIC):** Client enterprise representatives utilize a dedicated portal to submit shift schedules, forecast passenger volumes, and dispatch specific trip requests.
* **Passengers:** Scan in-cabin QR codes to access a rapid feedback interface. Passengers rate drivers on safety, professionalism, and punctuality, directly feeding the machine learning evaluation models.

---

## Local Development and Setup

### Prerequisites

Ensure your local development environment includes the following dependencies:

* Node.js v20+
* Flutter SDK
* Python 3.10+
* Supabase Account and CLI

### Running the System Locally

The backend analytics engine and the Flutter web portal must run concurrently in separate terminal instances.

**Terminal 1: Python Analytics Backend**

```bash
cd python

# Activate your virtual environment (Windows example)
.\Activate.ps1    

# Launch the Flask server
python app.py

```

**Terminal 2: Flutter Web Portal**

```bash
cd flutter

# Launch the Flutter web application
flutter run -d chrome --web-port 8080 --no-web-resources-cdn

```
