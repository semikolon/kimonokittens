import React from 'react';
import { Editor } from '@tiptap/react';

interface EditToolbarProps {
  editor: Editor | null;
}

export const EditToolbar: React.FC<EditToolbarProps> = ({ editor }) => {
  if (!editor) {
    return null;
  }

  return (
    <div className="border border-gray-300 rounded-t-lg p-2">
      <button
        onClick={() => editor.chain().focus().toggleBold().run()}
        className={editor.isActive('bold') ? 'is-active' : ''}
      >
        Bold
      </button>
      {/* Add more buttons for italic, headings, etc. */}
    </div>
  );
}; 