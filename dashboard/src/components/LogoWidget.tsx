import React from 'react'

export function LogoWidget() {
  return (
    <div className="flex flex-col items-center justify-center h-full">
      <img 
        src="/www/logo.png" 
        alt="Kimonokittens" 
        className="max-w-sm max-h-80 object-contain drop-shadow-2xl hover:scale-105 transition-transform duration-300"
      />
      <div className="mt-6 text-center text-gray-300 text-sm font-light tracking-wider">
        KIMONOKITTENS COLLECTIVE
      </div>
    </div>
  )
} 