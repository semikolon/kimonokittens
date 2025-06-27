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
    <div className="border border-gray-300 rounded-t-lg p-2 bg-gray-100 flex gap-2">
      <button
        onClick={() => editor.chain().focus().toggleBold().run()}
        className={`px-3 py-1 rounded text-sm ${
          editor.isActive('bold') 
            ? 'bg-blue-500 text-white' 
            : 'bg-white border hover:bg-gray-50'
        }`}
      >
        Bold
      </button>
      
      <button
        onClick={() => editor.chain().focus().toggleItalic().run()}
        className={`px-3 py-1 rounded text-sm ${
          editor.isActive('italic') 
            ? 'bg-blue-500 text-white' 
            : 'bg-white border hover:bg-gray-50'
        }`}
      >
        Italic
      </button>
      
      <button
        onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}
        className={`px-3 py-1 rounded text-sm ${
          editor.isActive('heading', { level: 2 }) 
            ? 'bg-blue-500 text-white' 
            : 'bg-white border hover:bg-gray-50'
        }`}
      >
        H2
      </button>
      
      <button
        onClick={() => editor.chain().focus().toggleBulletList().run()}
        className={`px-3 py-1 rounded text-sm ${
          editor.isActive('bulletList') 
            ? 'bg-blue-500 text-white' 
            : 'bg-white border hover:bg-gray-50'
        }`}
      >
        • List
      </button>
    </div>
  );
}; 