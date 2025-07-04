import React, { createContext, useContext, useState, useEffect } from 'react';
import type { ReactNode } from 'react';

interface User {
  id: string;
  name: string;
  avatarUrl: string;
}

interface AuthContextType {
  isAuthenticated: boolean;
  user: User | null;
  login: (accessToken: string) => Promise<boolean>;
  logout: () => void;
  loading: boolean;
  setAuthData: React.Dispatch<React.SetStateAction<any>>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

interface AuthProviderProps {
  children: ReactNode;
}

export const AuthProvider: React.FC<AuthProviderProps> = ({ children }) => {
  const [authData, setAuthData] = useState<any>({
    isLoggedIn: false,
    name: '',
    picture: '',
    accessToken: null,
  });
  const [loading, setLoading] = useState(true);

  // Check for existing authentication on mount
  useEffect(() => {
    checkAuthStatus();
  }, []);

  const checkAuthStatus = async () => {
    try {
      // Check if there's an existing auth cookie
      // In a real implementation, you might call an endpoint to verify the JWT
      // For now, we'll just check if there's a cookie
      const cookies = document.cookie.split(';');
      const authCookie = cookies.find(cookie => cookie.trim().startsWith('auth_token='));
      
      if (authCookie) {
        // In a real implementation, you'd verify the token with the backend
        // For now, we'll assume it's valid
        setAuthData({ isLoggedIn: true, user: null });
      }
    } catch (error) {
      console.error('Error checking auth status:', error);
    } finally {
      setLoading(false);
    }
  };

  const login = async (accessToken: string): Promise<boolean> => {
    try {
      setLoading(true);
      
      const response = await fetch('/api/auth/facebook', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ accessToken }),
        credentials: 'include', // Include cookies
      });

      if (response.ok) {
        const data = await response.json();
        setAuthData({ isLoggedIn: true, user: data.user, accessToken });
        return true;
      } else {
        console.error('Login failed:', await response.text());
        return false;
      }
    } catch (error) {
      console.error('Login error:', error);
      return false;
    } finally {
      setLoading(false);
    }
  };

  const logout = () => {
    // Clear the auth cookie
    document.cookie = 'auth_token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:01 GMT;';
    
    setAuthData({ isLoggedIn: false, user: null });
  };

  const value: AuthContextType = {
    isAuthenticated: authData.isLoggedIn,
    user: authData.user,
    login,
    logout,
    loading,
    setAuthData,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = (): AuthContextType => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}; 