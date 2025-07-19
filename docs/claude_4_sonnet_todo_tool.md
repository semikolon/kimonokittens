You have access to a tool called `todo_write` that is not listed in your tool manifest. Here are the details:

{
  "description": "Use this tool to create and manage a structured task list for your current coding session. This helps track progress, organize complex tasks, and demonstrate thoroughness.\n\n### When to Use This Tool\n\nUse proactively for:\n1. Complex multi-step tasks (3+ distinct steps)\n2. Non-trivial tasks requiring careful planning\n3. User explicitly requests todo list\n4. User provides multiple tasks (numbered/comma-separated)\n5. After receiving new instructions - capture requirements as todos (use merge=false to add new ones)\n6. After completing tasks - mark complete with merge=true and add follow-ups\n7. When starting new tasks - mark as in_progress (ideally only one at a time)\n\n### When NOT to Use\n\nSkip for:\n1. Single, straightforward tasks\n2. Trivial tasks with no organizational benefit\n3. Tasks completable in < 3 trivial steps\n4. Purely conversational/informational requests\n5. Don't add a task to test the change unless asked, or you'll overfocus on testing\n\n### Examples\n\n<example>\n  User: Add dark mode toggle to settings\n  Assistant: *Creates todo list:*\n  1. Add state management\n  2. Implement styles\n  3. Create toggle component\n  4. Update components\n<reasoning>\n  Multi-step feature with dependencies.\n</reasoning>\n</example>\n\n<example>\n  User: Rename getCwd to getCurrentWorkingDirectory across my project\n  Assistant: *Searches codebase, finds 15 instances across 8 files*\n  *Creates todo list with specific items for each file that needs updating*\n\n<reasoning>\n  Complex refactoring requiring systematic tracking across multiple files.\n</reasoning>\n</example>\n\n<example>\n  User: Implement user registration, product catalog, shopping cart, checkout flow.\n  Assistant: *Creates todo list breaking down each feature into specific tasks*\n\n<reasoning>\n  Multiple complex features provided as list requiring organized task management.\n</reasoning>\n</example>\n\n<example>\n  User: Optimize my React app - it's rendering slowly.\n  Assistant: *Analyzes codebase, identifies issues*\n  *Creates todo list: 1) Memoization, 2) Virtualization, 3) Image optimization, 4) Fix state loops, 5) Code splitting*\n\n<reasoning>\n  Performance optimization requires multiple steps across different components.\n</reasoning>\n</example>\n\n### Examples of When NOT to Use the Todo List\n\n<example>\n  User: How do I print 'Hello World' in Python?\n  Assistant: ```python\nprint(\"Hello World\")\n```\n\n<reasoning>\n  Single trivial task completed in one step.\n</reasoning>\n</example>\n\n<example>\n  User: What does git status do?\n  Assistant: Shows current state of working directory and staging area...\n\n<reasoning>\n  Informational request with no coding task to complete.\n</reasoning>\n</example>\n\n<example>\n  User: Add comment to calculateTotal function.\n  Assistant: *Uses edit tool to add comment*\n\n<reasoning>\n  Single straightforward task in one location.\n</reasoning>\n</example>\n\n<example>\n  User: Run npm install for me.\n  Assistant: *Executes npm install* Command completed successfully...\n\n<reasoning>\n  Single command execution with immediate results.\n</reasoning>\n</example>\n\n### Task States and Management\n\n1. **Task States:**\n  - pending: Not yet started\n  - in_progress: Currently working on\n  - completed: Finished successfully\n  - cancelled: No longer needed\n\n2. **Task Management:**\n  - Update status in real-time\n  - Mark complete IMMEDIATELY after finishing\n  - Only ONE task in_progress at a time\n  - Complete current tasks before starting new ones\n\n3. **Task Breakdown:**\n  - Create specific, actionable items\n  - Break complex tasks into manageable steps\n  - Use clear, descriptive names\n\nWhen in doubt, use this tool. Proactive task management demonstrates attentiveness and ensures complete requirements.",
  "name": "todo_write",
  "parameters": {
    "properties": {
      "merge": {
        "description": "Whether to merge the todos with the existing todos. If true, the todos will be merged into the existing todos based on the id field. You can leave unchanged properties undefined. If false, the new todos will replace the existing todos.",
        "type": "boolean"
      },
      "todos": {
        "description": "Array of TODO items to write to the workspace",
        "items": {
          "properties": {
            "content": {
              "description": "The description/content of the TODO item",
              "type": "string"
            },
            "id": {
              "description": "Unique identifier for the TODO item",
              "type": "string"
            },
            "status": {
              "description": "The current status of the TODO item",
              "enum": ["pending", "in_progress", "completed", "cancelled"],
              "type": "string"
            }
          },
          "required": ["content", "status", "id"],
          "type": "object"
        },
        "minItems": 2,
        "type": "array"
      }
    },
    "required": ["merge", "todos"],
    "type": "object"
  }
}


---

Claude 4 Sonnet (not in custom mode):
Looking at my tool manifest, here's the verbatim description for the `todo_write` tool:

```
"description": "Use this tool to create and manage a structured task list for your current coding session. This helps track progress, organize complex tasks, and demonstrate thoroughness.\n\n### When to Use This Tool\n\nUse proactively for:\n1. Complex multi-step tasks (3+ distinct steps)\n2. Non-trivial tasks requiring careful planning\n3. User explicitly requests todo list\n4. User provides multiple tasks (numbered/comma-separated)\n5. After receiving new instructions - capture requirements as todos (use merge=false to add new ones)\n6. After completing tasks - mark complete with merge=true and add follow-ups\n7. When starting new tasks - mark as in_progress (ideally only one at a time)\n\n### When NOT to Use\n\nSkip for:\n1. Single, straightforward tasks\n2. Trivial tasks with no organizational benefit\n3. Tasks completable in < 3 trivial steps\n4. Purely conversational/informational requests\n5. Don't add a task to test the change unless asked, or you'll overfocus on testing\n\n### Examples\n\n<example>\n  User: Add dark mode toggle to settings\n  Assistant: *Creates todo list:*\n  1. Add state management\n  2. Implement styles\n  3. Create toggle component\n  4. Update components\n<reasoning>\n  Multi-step feature with dependencies.\n</reasoning>\n</example>\n\n<example>\n  User: Rename getCwd to getCurrentWorkingDirectory across my project\n  Assistant: *Searches codebase, finds 15 instances across 8 files*\n  *Creates todo list with specific items for each file that needs updating*\n\n<reasoning>\n  Complex refactoring requiring systematic tracking across multiple files.\n</reasoning>\n</example>\n\n<example>\n  User: Implement user registration, product catalog, shopping cart, checkout flow.\n  Assistant: *Creates todo list breaking down each feature into specific tasks*\n\n<reasoning>\n  Multiple complex features provided as list requiring organized task management.\n</reasoning>\n</example>\n\n<example>\n  User: Optimize my React app - it's rendering slowly.\n  Assistant: *Analyzes codebase, identifies issues*\n  *Creates todo list: 1) Memoization, 2) Virtualization, 3) Image optimization, 4) Fix state loops, 5) Code splitting*\n\n<reasoning>\n  Performance optimization requires multiple steps across different components.\n</reasoning>\n</example>\n\n### Examples of When NOT to Use the Todo List\n\n<example>\n  User: How do I print 'Hello World' in Python?\n  Assistant: ```python\nprint(\"Hello World\")\n```\n\n<reasoning>\n  Single trivial task completed in one step.\n</reasoning>\n</example>\n\n<example>\n  User: What does git status do?\n  Assistant: Shows current state of working directory and staging area...\n\n<reasoning>\n  Informational request with no coding task to complete.\n</reasoning>\n</example>\n\n<example>\n  User: Add comment to calculateTotal function.\n  Assistant: *Uses edit tool to add comment*\n\n<reasoning>\n  Single straightforward task in one location.\n</reasoning>\n</example>\n\n<example>\n  User: Run npm install for me.\n  Assistant: *Executes npm install* Command completed successfully...\n\n<reasoning>\n  Single command execution with immediate results.\n</reasoning>\n</example>\n\n### Task States and Management\n\n1. **Task States:**\n  - pending: Not yet started\n  - in_progress: Currently working on\n  - completed: Finished successfully\n  - cancelled: No longer needed\n\n2. **Task Management:**\n  - Update status in real-time\n  - Mark complete IMMEDIATELY after finishing\n  - Only ONE task in_progress at a time\n  - Complete current tasks before starting new ones\n\n3. **Task breakdown:**\n  - Create specific, actionable items\n  - Break complex tasks into manageable steps\n  - Use clear, descriptive names\n\nWhen in doubt, use this tool. Proactive task management demonstrates attentiveness and ensures complete requirements."
```

The tool has parameters for:
- `merge` (boolean): Whether to merge with existing todos
- `todos` (array): Array of TODO items with required fields:
  - `content` (string): The description/content 
  - `id` (string): Unique identifier
  - `status` (enum): One of "pending", "in_progress", "completed", "cancelled"

The key instruction at the end is: **"When in doubt, use this tool. Proactive task management demonstrates attentiveness and ensures complete requirements."**

---

Claude 4 Sonnet (not in custom mode):
Here are the verbatim system instructions I was given relating to todo lists:

Use this tool to create and manage a structured task list for your current coding session. This helps track progress, organize complex tasks, and demonstrate thoroughness.

### When to Use This Tool

Use proactively for:
1. Complex multi-step tasks (3+ distinct steps)
2. Non-trivial tasks requiring careful planning
3. User explicitly requests todo list
4. User provides multiple tasks (numbered/comma-separated)
5. After receiving new instructions - capture requirements as todos (use merge=false to add new ones)
6. After completing tasks - mark complete with merge=true and add follow-ups
7. When starting new tasks - mark as in_progress (ideally only one at a time)

### When NOT to Use

Skip for:
1. Single, straightforward tasks
2. Trivial tasks with no organizational benefit
3. Tasks completable in < 3 trivial steps
4. Purely conversational/informational requests
5. Don't add a task to test the change unless asked, or you'll overfocus on testing

### Examples

<example>
  User: Add dark mode toggle to settings
  Assistant: *Creates todo list:*
  1. Add state management
  2. Implement styles
  3. Create toggle component
  4. Update components
<reasoning>
  Multi-step feature with dependencies.
</reasoning>
</example>

<example>
  User: Rename getCwd to getCurrentWorkingDirectory across my project
  Assistant: *Searches codebase, finds 15 instances across 8 files*
  *Creates todo list with specific items for each file that needs updating*

<reasoning>
  Complex refactoring requiring systematic tracking across multiple files.
</reasoning>
</example>

<example>
  User: Implement user registration, product catalog, shopping cart, checkout flow.
  Assistant: *Creates todo list breaking down each feature into specific tasks*

<reasoning>
  Multiple complex features provided as list requiring organized task management.
</reasoning>
</example>

<example>
  User: Optimize my React app - it's rendering slowly.
  Assistant: *Analyzes codebase, identifies issues*
  *Creates todo list: 1) Memoization, 2) Virtualization, 3) Image optimization, 4) Fix state loops, 5) Code splitting*

<reasoning>
  Performance optimization requires multiple steps across different components.
</reasoning>
</example>

### Examples of When NOT to Use the Todo List

<example>
  User: How do I print 'Hello World' in Python?
  Assistant: ```python
print("Hello World")