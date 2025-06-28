import React from 'react';
import FacebookLogin from 'react-facebook-login';
import { useAuth } from '../context/AuthContext';

interface LoginButtonProps {
  className?: string;
}

export const LoginButton: React.FC<LoginButtonProps> = ({ className = '' }) => {
  const { login, loading } = useAuth();

  const handleFacebookResponse = async (response: any) => {
    console.log('Facebook response:', response);
    
    if (response.accessToken) {
      const success = await login(response.accessToken);
      if (success) {
        console.log('Login successful');
      } else {
        console.error('Login failed');
      }
    } else {
      console.error('No access token received from Facebook');
    }
  };

  if (loading) {
    return (
      <button 
        disabled 
        className={`px-4 py-2 bg-purple-400 text-white rounded-lg cursor-not-allowed ${className}`}
      >
        Laddar...
      </button>
    );
  }

  return (
    <FacebookLogin
      appId={import.meta.env.VITE_FACEBOOK_APP_ID || 'your-facebook-app-id'}
      autoLoad={false}
      fields="name,email,picture"
      callback={handleFacebookResponse}
      textButton="Logga in med Facebook"
      cssClass={`inline-flex items-center px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors duration-200 ${className}`}
      icon="fa-facebook"
    />
  );
}; 