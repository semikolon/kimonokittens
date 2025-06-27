import React, { useState } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import { EditToolbar } from './EditToolbar';

export const Editor: React.FC = () => {
  const [isSaving, setIsSaving] = useState(false);

  const editor = useEditor({
    extensions: [
      StarterKit,
    ],
    content: '<p>Start writing your proposal...</p>',
    editorProps: {
      attributes: {
        class: 'prose prose-sm sm:prose lg:prose-lg xl:prose-2xl mx-auto focus:outline-none min-h-[200px] p-4 border rounded-b-lg',
      },
    },
  });

  const saveProposal = async () => {
    if (!editor) return;

    const content = editor.getHTML();
    setIsSaving(true);

    try {
      const response = await fetch('/api/handbook/proposals', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ content }),
      });

      if (response.ok) {
        const newProposal = await response.json();
        console.log('Proposal created:', newProposal);
        
        // Clear the editor
        editor.commands.setContent('<p>Start writing your proposal...</p>');
        
        // You could add a toast notification here
        alert('Proposal saved successfully!');
      } else {
        throw new Error('Failed to save proposal');
      }
    } catch (error) {
      console.error('Error saving proposal:', error);
      alert('Error saving proposal. Please try again.');
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="border rounded-lg bg-white">
      <div className="p-4 border-b">
        <h2 className="text-xl font-bold">Create New Proposal</h2>
      </div>
      
      <EditToolbar editor={editor} />
      
      <EditorContent editor={editor} />
      
      <div className="p-4 border-t bg-gray-50">
        <button
          onClick={saveProposal}
          disabled={isSaving}
          className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {isSaving ? 'Saving...' : 'Save Proposal'}
        </button>
      </div>
    </div>
  );
}; 