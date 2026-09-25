# SecurePark — Campus Admin Web Application

A clean, high-utility administration portal for **SecurePark — QR Digital Custody & Exit Verification System** for NCST (National College of Science and Technology).

---

## 🎨 Color Palette & Design Hierarchy

The design adopts the core institutional colors from [`lib/theme/ncst_theme.dart`](file:///c:/Users/ethan/OneDrive/Documents/systemforInteg/lib/theme/ncst_theme.dart):

- **Navy (`#1A3B8B`, `#0F265C`)**: Sidebar, active navigation, primary action buttons
- **Slate (`#F8FAFC`, `#F1F5F9`, `#E2E8F0`, `#0F172A`)**: Work surfaces, data table borders, clear typography
- **Green (`#16A34A`)**: Vehicles currently inside campus
- **Crimson (`#D92128`)**: Flagged / blocked vehicle alerts

---

## 🧭 Architecture

1. **Sidebar Navigation**:
   - **User Profile on Top**: Operator avatar, name (`Roberto Mendoza`), and role (`Campus Security`).
   - **Divider**: A clean horizontal rule directly below the user.
   - **Navigation Menu**: Two distinct sections:
     - `Dashboard`
     - `Account Creation`
   - **No Upper Bar in Workspace**: Full vertical space dedicated directly to work.

2. **Dashboard**:
   - 4 Clean Metrics: `Vehicles Inside`, `Flagged / Blocked`, `Total Entries & Exits`, and `Registered Fleet`.
   - Operations Data Table: Displays `Plate`, `Owner`, `Driver`, `Status`, `Gate`, and `Time` with live search and status filters (`All`, `Inside`, `Flagged`).

3. **Account Creation UI**:
   - Straightforward, clean form with sections for `Owner Information`, `Vehicle Details`, and dynamic `Authorized Drivers`.

---

## 💻 Running Locally

Open [`index.html`](file:///c:/Users/ethan/OneDrive/Documents/systemforInteg/web-app-admin/index.html) in any web browser.
