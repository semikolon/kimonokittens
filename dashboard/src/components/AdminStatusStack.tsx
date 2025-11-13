import React from 'react'
import { useData } from '../context/DataContext'
import { AdminUnlockIndicator } from './admin/AdminUnlockIndicator'
import { DeploymentBanner } from './DeploymentBanner'

export const AdminStatusStack: React.FC = () => {
  const { state } = useData()
  const showPIN = state.connectionStatus === 'open'
  const showDeploy = Boolean(state.deploymentStatus?.pending)

  if (!showPIN && !showDeploy) return null

  return (
    <div className="fixed bottom-4 right-4 flex flex-col items-end gap-3 z-50 pointer-events-none">
      {showDeploy && (
        <div className="pointer-events-auto">
          <DeploymentBanner compact />
        </div>
      )}
      {showPIN && (
        <div className="pointer-events-auto">
          <AdminUnlockIndicator compact />
        </div>
      )}
    </div>
  )
}
