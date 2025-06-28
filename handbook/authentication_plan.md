# Authentication Master Plan: Facebook Login

**Core Concept:** The user will click a "Login with Facebook" button in the frontend. This will trigger the Facebook login popup. After they approve, the frontend receives a temporary token, sends it to our backend, and our backend exchanges it for a secure session token (JWT) that it returns to the client as an `HttpOnly` cookie. The backend will also use this opportunity to create or update the user's `Tenant` record in the database.

---

### **Phase 1: Backend Configuration & Database Prep (The Foundation)**

1.  **Create a Facebook App (USER ACTION):**
    *   Go to the [Meta for Developers](https://developers.facebook.com/) portal.
    *   Create a new App of type "Consumer".
    *   Under "App settings" -> "Basic", find your **App ID** and **App Secret**.
    *   Add a "Facebook Login" product. In its settings, add `http://localhost:6464` and your production domain as valid OAuth redirect URIs.

2.  **Set Environment Variables:**
    *   In your project's `.env` file (or wherever you manage secrets), add the credentials from the step above:
        ```
        FACEBOOK_APP_ID=your-app-id
        FACEBOOK_APP_SECRET=your-app-secret
        JWT_SECRET=a-long-random-secure-string-you-generate
        ```
    *   The `JWT_SECRET` is crucial for signing our session tokens.

3.  **Update the Database Schema:**
    *   We need to add a field to our `Tenant` model to store the user's unique Facebook ID.
    *   **Action:** Edit `handbook/prisma/schema.prisma` and add `facebookId`.
        ```prisma
        model Tenant {
          id           String   @id @default(cuid())
          facebookId   String?  @unique // <-- ADD THIS LINE
          name         String
          email        String   @unique
          //... existing fields
        }
        ```

4.  **Run Database Migration:**
    *   From the `handbook/` directory, run `npx prisma migrate dev --name add_facebook_id_to_tenant` to apply the schema change.

5.  **Add Backend Dependencies:**
    *   Add `gem 'httparty'` and `gem 'jwt'` to your root `Gemfile` to handle HTTP requests to Facebook and to create/verify JSON Web Tokens.
    *   Run `bundle install`.

---

### **Phase 2: Backend API Endpoint (The Logic)**

1.  **Create a New Auth Handler:**
    *   Create a new file: `handlers/auth_handler.rb`.
    *   This handler will contain the logic for our new authentication endpoint.

2.  **Implement the Callback Endpoint (`POST /api/auth/facebook`):**
    *   In `auth_handler.rb`, create the endpoint. When it receives a short-lived `accessToken` from the frontend, it will:
        1.  **Verify the token** with Facebook's debug endpoint to ensure it's valid.
        2.  **Fetch User Profile:** Use the token to make a GET request to Facebook's Graph API (`/me?fields=id,first_name,picture.type(large)`).
        3.  **Find or Create Tenant:**
            *   Look for a `Tenant` in the database where `facebookId` matches the ID from the profile.
            *   If a `Tenant` exists, use it.
            *   If not, create a new `Tenant` using the `first_name` and `picture.url` from the profile.
        4.  **Generate JWT:** Create a JWT that contains the `tenantId` and an expiry date (e.g., 7 days). Sign it with your `JWT_SECRET`.
        5.  **Set Secure Cookie:** Send the JWT back to the client in an `HttpOnly`, `Secure`, `SameSite=Strict` cookie. This is the most secure way to store session tokens.
        6.  **Return User Data:** Respond with a JSON object containing the tenant's info (`{ id, name, avatarUrl }`).

3.  **Mount the Handler:**
    *   In `json_server.rb`, mount the new handler: `server.mount "/api/auth", AuthHandler`.

---

### **Phase 3: Frontend Implementation (The UI)**

1.  **Install Frontend Dependency:**
    *   In the `handbook/frontend` directory, run `npm install react-facebook-login`. This package provides a convenient button component that handles the popup flow.

2.  **Create an `AuthContext`:**
    *   Create a new file `src/context/AuthContext.tsx`.
    *   This context will manage the global authentication state (`isAuthenticated`, `user`, `logout`). It will provide this state to all components wrapped within it.

3.  **Create a Login Component:**
    *   Create `src/components/LoginButton.tsx`.
    *   This component will use the `react-facebook-login` package. On a successful login, it receives the `accessToken` from Facebook and immediately calls our backend endpoint (`POST /api/auth/facebook`).
    *   On a successful response from our backend, it will update the `AuthContext` with the user's data.

4.  **Integrate into `App.tsx`:**
    *   Wrap the main layout in `App.tsx` with your new `AuthProvider`.
    *   In the header, conditionally render the `LoginButton` if the user is not authenticated.
    *   If the user *is* authenticated, display their profile picture and name, along with a "Logout" button. The `logout` function should simply clear the auth state from the context and could optionally call a backend endpoint to invalidate the cookie. 