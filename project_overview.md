# Flutter TBS Mobile App - Implementation Plan

## Project Overview
- **App Name**: TBS
- **Framework**: Flutter (Latest Version)
- **Backend**: Laravel API (fjpwl)
- **Target Platforms**: iOS & Android
- **Key Pages**: Login, Menu, Pre-In, Pre-Out, Process

## Phase 1: Foundation & Setup (Weeks 1-2)

### 1.1 Project Structure
```
tbs_mobile/
├── lib/
│   ├── main.dart
│   ├── config/
│   │   ├── api_config.dart
│   │   ├── app_constants.dart
│   │   └── theme.dart
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── container_model.dart
│   │   ├── gate_record_model.dart
│   │   └── process_model.dart
│   ├── services/
│   │   ├── api_service.dart
│   │   ├── auth_service.dart
│   │   ├── storage_service.dart
│   │   └── gate_service.dart
│   ├── providers/ (State Management)
│   │   ├── auth_provider.dart
│   │   ├── gate_provider.dart
│   │   └── app_provider.dart
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── login_screen.dart
│   │   ├── menu_screen.dart
│   │   ├── pre_in_screen.dart
│   │   ├── pre_out_screen.dart
│   │   └── process_screen.dart
│   ├── widgets/
│   │   ├── custom_button.dart
│   │   ├── custom_input.dart
│   │   ├── loading_widget.dart
│   │   └── tbs_app_bar.dart
│   └── utils/
│       ├── validators.dart
│       └── helpers.dart
├── assets/
│   ├── images/
│   │   ├── tbs.jpg (logo)
│   │   ├── tbs_loading.png
│   │   └── tbs_icon.png
│   └── fonts/
├── pubspec.yaml
└── README.md
```

### 1.2 Dependencies (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  provider: ^6.0.0
  shared_preferences: ^2.0.0
  flutter_secure_storage: ^9.0.0
  dio: ^5.3.0
  get_it: ^7.6.0
  intl: ^0.19.0
  connectivity_plus: ^5.0.0
  flutter_spinkit: ^5.2.0
  image_picker: ^1.0.0
  permission_handler: ^11.4.0
  
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_linter: ^3.0.0
```

### 1.3 App Configuration Files
- API base URL configuration (Laravel backend)
- App constants (timeout, retry logic, etc.)
- Theme configuration (TBS branding colors)
- Asset paths for tbs.jpg, icons

### 1.4 Models Creation
- UserModel (username, user_id, token, role, permissions)
- ContainerModel (container_id, size, type, status)
- GateRecordModel (gate_id, container_id, in_time, out_time, status)
- ProcessModel (process_id, container_id, details, timestamp)

### 1.5 Core Services
- **ApiService**: HTTP client wrapper with interceptors, error handling
- **AuthService**: Login/logout, token management
- **StorageService**: SharedPreferences for local data
- **GateService**: Pre-in/pre-out/process operations

### Deliverables Phase 1:
- ✓ Project structure initialized
- ✓ Pubspec.yaml with all dependencies
- ✓ API configuration ready
- ✓ Models defined
- ✓ Base services created
- ✓ Theme/styling configured

---

## Phase 2: Pages & UI Implementation (Weeks 3-4)

### 2.1 Splash Screen
- **Duration**: 3 seconds
- **Elements**: TBS logo (tbs.jpg), loading indicator
- **Logic**: Check if user is already logged in (token in SharedPreferences)
  - If logged in → Navigate to Menu
  - If not → Navigate to Login

### 2.2 Login Screen
**UI Elements:**
- TBS Logo (tbs.jpg) at top
- Username TextField (with validation)
- Password TextField (masked input)
- Login Button (rounded, TBS styled)
- Error message display
- Loading indicator during login

**Functionality:**
- Input validation (username & password required)
- Call `POST /api/login` from Laravel
- Store auth token (Bearer token from response)
- Store user_id & user details
- Navigation to Menu on success
- Display error messages on failure
- Offline detection with error message

### 2.3 Menu Screen
**UI Elements:**
- TBS Header with user greeting ("Welcome, [username]")
- Two large action buttons:
  - GATE IN (blue button with icon)
  - GATE OUT (red button with icon)
- Logout button (bottom, subtle styling)

**Functionality:**
- Display logged-in user info
- Navigation to Pre-In screen on GATE IN tap
- Navigation to Pre-Out screen on GATE OUT tap
- Logout: Clear token, clear user data, navigate to Login
- Check network status on load

### 2.4 Pre-In Screen
**UI Elements:**
- Header: "Pre-Gate Container (IN)"
- Container Information Display:
  - Container ID (scan or manual entry)
  - Container Size (auto-filled from database)
  - Container Type (dropdown)
  - Status (read-only display)
- Action Buttons:
  - Scan QR/Barcode button (camera icon)
  - Manual Entry option
  - Submit button
- Cancel button to return to Menu

**Functionality:**
- Scan QR code to get container_id
- OR manually input container_id
- Validate container exists in system via API
- Display container details from database
- Allow user to confirm pre-in data
- Submit pre-in request to Laravel API
- Show success/error message
- Return to Menu

### 2.5 Pre-Out Screen
**UI Elements:**
- Header: "Pre-Gate Container (OUT)"
- Similar structure to Pre-In
- Container Information Display
- Exit Reason dropdown (optional)
- Discharge confirmation checkbox

**Functionality:**
- Similar flow to Pre-In but for gate out
- Validate container status (must be "IN")
- Submit pre-out request to Laravel API
- Return to Menu

### 2.6 Process Screen
**UI Elements:**
- Header: "Process Gate Record"
- List/Table showing:
  - Container ID
  - Container Size
  - In Time
  - Out Time
  - Duration
  - Status
- Action buttons:
  - View Details
  - Print/Export
  - Refresh

**Functionality:**
- Fetch recent gate records from Laravel API
- Display in scrollable list
- Show detailed info when tapped
- Export/print functionality (optional for Phase 1)
- Pull-to-refresh to reload data

### 2.7 State Management (Provider)
- **AuthProvider**: Manage login/logout state, user info, token
- **GateProvider**: Manage gate in/out operations, container data
- **AppProvider**: Manage app-wide state, connectivity status

### 2.8 Error Handling & Validation
- Network error handling with retry logic
- Form validation (username, password, container ID)
- Token expiration and refresh logic
- Display user-friendly error messages

### Deliverables Phase 2:
- ✓ All 6 screens implemented with UI
- ✓ Navigation flow complete
- ✓ Input validation working
- ✓ Provider state management set up
- ✓ API calls integrated (mock ready for Phase 3)
- ✓ Loading states and error messages
- ✓ Offline detection implemented

---

## Phase 3: API Integration & Testing (Weeks 5-6)

### 3.1 API Endpoints Integration

**Authentication:**
```
POST /api/login
  Request: { username, password }
  Response: { token, user_id, username, role }

POST /api/logout
  Headers: { Authorization: Bearer {token} }
  
GET /api/me
  Headers: { Authorization: Bearer {token} }
```

**Gate Operations:**
```
GET /api/gateinout/container/{id}
  Get container details

POST /api/gateinout/pre-in
  Request: { container_id, user_id }
  Response: { gate_id, status, timestamp }

POST /api/gateinout/pre-out
  Request: { container_id, user_id, exit_reason? }
  Response: { gate_id, status, timestamp }

GET /api/gateinout/process-list
  Get list of recent process records
  Params: { limit, offset, filters }
```

### 3.2 Token Management
- Store JWT token in Flutter Secure Storage
- Implement token refresh mechanism
- Auto-logout on token expiration
- Implement request interceptors in Dio/Http client

### 3.3 Database Sync (Optional)
- Local SQLite cache for offline capability
- Sync when connectivity restored
- Cache recent containers and records

### 3.4 Testing & QA
- **Unit Tests**: Services, models, validators
- **Widget Tests**: Individual screens, components
- **Integration Tests**: Full user flows
- **API Tests**: All endpoints with Laravel backend
- **Performance Tests**: Loading times, data handling

### 3.5 Error Scenarios Testing
- Invalid credentials
- Network timeouts
- Server errors (500, 404, etc.)
- Token expiration
- Concurrent requests
- Container not found
- Duplicate gate entries

### 3.6 Build & Release Preparation
- Code optimization and cleanup
- Asset optimization (image compression)
- ProGuard configuration for Android
- iOS code signing setup
- Build APK and IPA
- Version management

### Deliverables Phase 3:
- ✓ All API endpoints integrated with Laravel
- ✓ Token refresh mechanism working
- ✓ Comprehensive error handling
- ✓ Full test coverage
- ✓ Performance optimized
- ✓ Ready for production build

---

## Architecture Diagram

```
┌─────────────┐
│  Flutter    │
│    App      │
└──────┬──────┘
       │
       ├─ Screens Layer
       │  ├── Login
       │  ├── Menu
       │  ├── Pre-In
       │  ├── Pre-Out
       │  └── Process
       │
       ├─ Provider Layer (State Management)
       │  ├── AuthProvider
       │  ├── GateProvider
       │  └── AppProvider
       │
       ├─ Services Layer
       │  ├── ApiService (Dio/Http)
       │  ├── AuthService
       │  ├── GateService
       │  └── StorageService
       │
       └─ Data Layer
          ├── Models
          ├── Local Storage (SharedPreferences)
          └── Secure Storage (Tokens)
       
       ↕ (HTTP/REST)
       
┌─────────────────────────────┐
│  Laravel API (fjpwl)        │
│  ─────────────────────────  │
│  ├── /api/login             │
│  ├── /api/logout            │
│  ├── /api/gateinout/*       │
│  ├── /api/inventory/*       │
│  └── Authentication Layer   │
│      (Sanctum/JWT)          │
└─────────────┬───────────────┘
              │
        ┌─────▼────────┐
        │   Database   │
        │   (MySQL)    │
        └──────────────┘
```

---

## API Request/Response Examples

### Login Example
**Request:**
```
POST http://localhost:8000/api/login
Content-Type: application/json

{
  "username": "user123",
  "password": "password123"
}
```

**Response:**
```json
{
  "token": "1|8kZbZLBnZbZ9Xz...",
  "user_id": 1,
  "username": "user123",
  "name": "John Doe",
  "role": "operator"
}
```

### Pre-In Request Example
**Request:**
```
POST http://localhost:8000/api/gateinout/pre-in
Authorization: Bearer 1|8kZbZLBnZbZ9Xz...
Content-Type: application/json

{
  "container_id": "TCK0000001",
  "user_id": 1
}
```

**Response:**
```json
{
  "gate_id": 101,
  "container_id": "TCK0000001",
  "in_time": "2024-07-15 10:30:00",
  "status": "in_progress",
  "container_details": {
    "size": "20ft",
    "type": "Standard",
    "status": "active"
  }
}
```

---

## Development Timeline Summary

| Phase | Duration | Key Deliverables | Status |
|-------|----------|------------------|--------|
| Phase 1: Foundation | 2 weeks | Project setup, services, models | Not Started |
| Phase 2: UI & Flow | 2 weeks | All screens, navigation, state mgmt | Not Started |
| Phase 3: Integration & Testing | 2 weeks | API integration, testing, deployment | Not Started |
| **Total** | **6 weeks** | **Production-ready app** | **Planning** |

---

## Additional Considerations

### Security
- Use Flutter Secure Storage for tokens
- Implement certificate pinning
- Input sanitization
- HTTPS only communication

### Performance
- Lazy load images
- Implement pagination for lists
- Cache frequently accessed data
- Optimize API calls

### UX/UI
- Responsive design for different screen sizes
- Dark mode support (optional)
- Loading indicators for all async operations
- Clear error messages
- Intuitive navigation

### Offline Capabilities
- Local SQLite database for caching
- Queue failed requests
- Sync when online
- Offline mode indication

### Future Enhancements
- Photo capture for containers
- GPS tracking
- Push notifications
- Advanced reporting
- Multi-user support
- Dark theme
