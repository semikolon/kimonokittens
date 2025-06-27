import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { WikiPage } from './WikiPage';

describe('WikiPage', () => {
  it('renders the title', () => {
    render(<WikiPage title="Test Page" content="<p>Test content</p>" />);
    
    const titleElement = screen.getByText('Test Page');
    expect(titleElement).toBeInTheDocument();
  });

  it('renders HTML content', () => {
    render(<WikiPage title="Test" content="<p>Test paragraph</p><ul><li>Item 1</li></ul>" />);
    
    const paragraph = screen.getByText('Test paragraph');
    expect(paragraph).toBeInTheDocument();
    
    const listItem = screen.getByText('Item 1');
    expect(listItem).toBeInTheDocument();
  });

  it('applies prose styling classes', () => {
    const { container } = render(<WikiPage title="Test" content="<p>Content</p>" />);
    
    const article = container.querySelector('article');
    expect(article).toHaveClass('prose', 'lg:prose-xl');
  });
}); 