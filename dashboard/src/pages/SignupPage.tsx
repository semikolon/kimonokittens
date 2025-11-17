import { useState } from 'react'
import SignupForm from '../components/signup/SignupForm'
import SuccessModal from '../components/signup/SuccessModal'

export default function SignupPage() {
  const [showSuccess, setShowSuccess] = useState(false)

  return (
    <div className="min-h-screen relative overflow-hidden">
      {/* Animated gradient blobs background (shared from App.tsx) */}
      <div className="fixed inset-0 h-full w-full opacity-35 blur-[50px]" style={{ zIndex: 2 }}>
        <div className="absolute w-[60%] h-[60%] top-[10%] left-[10%] bg-[radial-gradient(ellipse_at_center,_rgba(68,25,150,0.38)_0%,_rgba(68,25,150,0)_70%)] mix-blend-screen animate-dashboard-first" />
        <div className="absolute w-[50%] h-[50%] top-[20%] right-[15%] bg-[radial-gradient(ellipse_at_center,_rgba(120,40,200,0.35)_0%,_rgba(120,40,200,0)_70%)] mix-blend-screen animate-dashboard-second" />
        <div className="absolute w-[55%] h-[55%] bottom-[15%] left-[20%] bg-[radial-gradient(ellipse_at_center,_rgba(100,30,180,0.36)_0%,_rgba(100,30,180,0)_70%)] mix-blend-screen animate-dashboard-third" />
        <div className="absolute w-[45%] h-[45%] bottom-[25%] right-[20%] bg-[radial-gradient(ellipse_at_center,_rgba(90,35,170,0.34)_0%,_rgba(90,35,170,0)_70%)] mix-blend-screen animate-dashboard-fourth" />
        <div className="absolute w-[50%] h-[50%] top-[30%] left-[35%] bg-[radial-gradient(ellipse_at_center,_rgba(110,45,190,0.33)_0%,_rgba(110,45,190,0)_70%)] mix-blend-screen animate-dashboard-fifth" />
      </div>

      {/* Main content */}
      <div className="relative z-10 container mx-auto px-4 py-12">
        {/* Header: Logo + Heading horizontal layout */}
        <div className="flex flex-col md:flex-row items-center justify-center gap-8 mb-8">
          <h1 className="font-horsemen text-4xl md:text-5xl text-purple-100 uppercase tracking-wide text-center md:text-left">
            Intresseanmälan
          </h1>
          <img
            src="/logo.png"
            alt="Kimonokittens"
            className="w-full max-w-[400px] md:w-[400px]"
          />
        </div>

        {/* Subheading */}
        <p className="text-center text-purple-200 text-lg mb-12">
          Fyll i formuläret nedan så kontaktar vi dig inom några dagar.
        </p>

        {/* Form container */}
        <div className="max-w-[600px] mx-auto w-full md:w-[60%]">
          <SignupForm onSuccess={() => setShowSuccess(true)} />
        </div>
      </div>

      {/* Success modal */}
      {showSuccess && (
        <SuccessModal onClose={() => setShowSuccess(false)} />
      )}
    </div>
  )
}
