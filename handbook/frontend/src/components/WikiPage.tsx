import React from 'react';

interface WikiPageProps {
  title: string;
  content: string; // This will later be HTML from TipTap
}

export const WikiPage: React.FC<WikiPageProps> = ({ title, content }) => {
  return (
    <article className="prose lg:prose-xl">
      <h1>{title}</h1>
      <div dangerouslySetInnerHTML={{ __html: content }} />
    </article>
  );
}; 