declare module 'react-facebook-login' {
  import { ComponentType } from 'react';

  interface FacebookLoginProps {
    appId: string;
    autoLoad?: boolean;
    fields?: string;
    callback: (response: any) => void;
    textButton?: string;
    cssClass?: string;
    icon?: string;
    scope?: string;
    xfbml?: boolean;
    cookie?: boolean;
    version?: string;
    language?: string;
    onClick?: () => void;
    onFailure?: (error: any) => void;
    render?: (props: any) => JSX.Element;
  }

  const FacebookLogin: ComponentType<FacebookLoginProps>;
  export default FacebookLogin;
} 