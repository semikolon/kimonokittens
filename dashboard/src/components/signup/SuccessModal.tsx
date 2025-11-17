import { X } from 'lucide-react'

interface SuccessModalProps {
  onClose: () => void
}

export default function SuccessModal({ onClose }: SuccessModalProps) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="bg-slate-900 border border-purple-500/30 rounded-2xl p-8 max-w-md mx-4 relative
                   shadow-2xl shadow-purple-500/20"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Close button */}
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-purple-300 hover:text-purple-100 transition-colors"
        >
          <X size={24} />
        </button>

        {/* Success message */}
        <div className="text-center">
          <div className="text-6xl mb-4">✨</div>
          <h2 className="text-2xl font-bold text-purple-100 mb-2">
            Tack för din ansökan!
          </h2>
          <p className="text-purple-200">
            Vi kontaktar dig inom några dagar.
          </p>
        </div>
      </div>
    </div>
  )
}
