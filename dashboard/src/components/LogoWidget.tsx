import React from 'react'

export function LogoWidget() {
  return (
    <div className="flex flex-col items-center justify-center">
      <img 
        src="/www/logo.png" 
        alt="Kimonokittens" 
        className="max-w-md max-h-96 object-contain"
      />
    </div>
  )
} 