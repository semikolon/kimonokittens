import React from 'react'

type WidgetVariant = 'default' | 'hero' | 'compact' | 'wide'

interface WidgetContainerProps {
  title: string
  variant?: WidgetVariant
  className?: string
  children: React.ReactNode
}

const widgetVariants = {
  default: {
    containerClass: 'widget',
    titleClass: 'widget-title',
    contentClass: 'widget-content'
  },
  hero: {
    containerClass: 'widget widget-hero',
    titleClass: 'widget-title text-lg font-bold',
    contentClass: 'widget-content text-lg'
  },
  compact: {
    containerClass: 'widget p-3',
    titleClass: 'widget-title text-sm',
    contentClass: 'widget-content text-sm'
  },
  wide: {
    containerClass: 'widget',
    titleClass: 'widget-title text-base',
    contentClass: 'widget-content'
  }
}

export function WidgetContainer({
  title,
  variant = 'default',
  className = '',
  children
}: WidgetContainerProps) {
  const config = widgetVariants[variant]

  return (
    <div className={`${config.containerClass} ${className}`}>
      <div className={config.titleClass}>{title}</div>
      <div className={config.contentClass}>
        {children}
      </div>
    </div>
  )
}