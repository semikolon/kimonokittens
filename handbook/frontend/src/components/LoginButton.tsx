import React from 'react';
import FacebookLogin from '@greatsumini/react-facebook-login';
import { useAuth } from '../context/AuthContext';

const LoginButton: React.FC = () => {
  const { setAuthData, login } = useAuth();

  const handleSuccess = (response: any) => {
    console.log('Login Success!', response);
    // The `login` function from our context expects the accessToken
    login(response.accessToken);
  };

  const handleFail = (error: any) => {
    console.log('Login Failed!', error);
    setAuthData({ isLoggedIn: false, name: '', picture: '', accessToken: null });
  };

  const handleProfileSuccess = (response: any) => {
    console.log('Get Profile Success!', response);
    // This callback provides user profile data.
    // We can use this to enrich our auth context.
    setAuthData((prev: any) => ({
      ...prev,
      isLoggedIn: true,
      name: response.name || 'User',
      picture: response.picture?.data?.url || ''
    }));
  };

  return (
    <FacebookLogin
      appId={import.meta.env.VITE_FACEBOOK_APP_ID || ''}
      onSuccess={handleSuccess}
      onFail={handleFail}
      onProfileSuccess={handleProfileSuccess}
      style={{
        backgroundColor: '#4267b2',
        color: '#fff',
        fontSize: '16px',
        padding: '10px 16px',
        border: 'none',
        borderRadius: '4px',
        cursor: 'pointer',
      }}
    />
  );
};

export default LoginButton; 