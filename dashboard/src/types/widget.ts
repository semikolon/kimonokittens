export interface WidgetProps {
  variant?: 'default' | 'hero' | 'compact' | 'wide'
  priority?: 'high' | 'medium' | 'low'
  className?: string
}

export interface WidgetVariantConfig {
  containerClass: string
  titleClass: string
  contentClass: string
}

export const widgetVariants: Record<NonNullable<WidgetProps['variant']>, WidgetVariantConfig> = {
  default: {
    containerClass: 'widget',
    titleClass: 'widget-title',
    contentClass: 'widget-content'
  },
  hero: {
    containerClass: 'widget widget-hero',
    titleClass: 'widget-title text-lg',
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