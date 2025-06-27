# Handoff Plan for Claude: Git-Backed Proposal System - PHASE 2

**Objective:** Complete the remaining tasks for the Git-backed proposal workflow and update the test suite.

## ✅ COMPLETED WORK

### Phase 1: Core Git Implementation ✅ DONE
- [x] **Fixed `Gemfile`:** Added `rugged` gem and resolved dependency issues
- [x] **Implemented Git Repository Integration:** Added `HandbookHandler.repo` class method  
- [x] **Re-implemented `GET /api/handbook/proposals`:** Now lists Git branches instead of in-memory array
- [x] **Re-implemented `POST /api/handbook/proposals`:** Creates Git branches with format `proposals/author/timestamp-description`
- [x] **Re-implemented `POST /api/handbook/proposals/:id/approve`:** Adds approval files and auto-merges after 2 approvals
- [x] **Fixed Agoo Routing:** Changed from `"/api/handbook/*"` to `"/api/handbook/**"` for deep path support
- [x] **Made SSL Conditional:** Updated `json_server.rb` to work in development without SSL certificates
- [x] **End-to-End Testing:** Successfully tested complete workflow from proposal creation to merge

### Test Results ✅ VERIFIED
- ✅ Proposal creation creates Git branch: `proposals/Fredrik/1751054070-update-handbook-docs-test-md`
- ✅ First approval adds `.approval.Alice` file and returns `{"approvals":1,"approvers":["Alice"]}`
- ✅ Second approval triggers automatic merge with `{"merge_status":"merged"}`
- ✅ Proposal branch is deleted after successful merge
- ✅ Changes are merged to master branch with proper commit message
- ✅ Proposals list becomes empty after merge

---

## 🎯 REMAINING TASKS

### Phase 2: Refinement and Testing

1. **Clean Up Merge Logic (HIGH PRIORITY)**
   - **Problem:** The current merge includes approval files (`.approval.*`) in the final master branch
   - **Solution:** Modify the merge logic to exclude approval files from the final merge
   - **Location:** `handlers/handbook_handler.rb` in the approval endpoint merge section
   - **Implementation:** Create a clean tree without approval files before creating the merge commit

2. **Update Backend Test Suite**
   - **File:** `spec/handbook_handler_spec.rb`
   - **Changes Needed:**
     - Remove all references to `@@proposals` array
     - Mock `Rugged::Repository` and `Rugged::Branch` objects
     - Update test expectations for Git branch names as proposal IDs
     - Add tests for merge conflicts scenario
     - Test approval file creation and counting

3. **Update Frontend for Git Integration**
   - **Files:** `handbook/frontend/src/components/ProposalList.tsx`, `Editor.tsx`
   - **Changes Needed:**
     - Handle branch names as proposal IDs (instead of numeric IDs)
     - Update URL encoding for approval requests
     - Add UI for merge conflict status
     - Test with new API response format

4. **Add Conflict Resolution**
   - **Enhancement:** When `merge_status: 'conflict'` is returned, provide user guidance
   - **Frontend:** Show conflict warning with instructions for manual resolution
   - **Backend:** Consider adding a "force merge" endpoint for admins

5. **Remove Debug Logging**
   - **File:** `handlers/handbook_handler.rb`
   - **Action:** Remove all `puts "DEBUG: ..."` statements
   - **File:** `test_handbook_server.rb`
   - **Action:** Remove test endpoint

6. **Update Main Server Configuration**
   - **File:** `json_server.rb`
   - **Action:** Update the main server to use `"/api/handbook/**"` routing pattern

### Phase 3: Documentation and Cleanup

7. **Update TODO.md**
   - Mark Phase 7.1 (Git-backed workflow) as complete
   - Update status of testing phase
   - Document the new API endpoints and response formats

8. **Integration Testing**
   - Test the full frontend + backend integration
   - Verify the React components work with Git branch IDs
   - Test edge cases (empty proposals, approval by same user twice, etc.)

---

## 🚀 CURRENT STATUS

The core Git-backed proposal workflow is **fully functional** and tested. The system successfully:
- Creates proposal branches from user submissions
- Tracks approvals using Git commits with approval files
- Automatically merges to master after 2 approvals
- Cleans up proposal branches after merge
- Handles the complete lifecycle in Git

The main remaining work is **cleanup, testing, and frontend integration** rather than core functionality.

---

## 📝 IMPLEMENTATION NOTES

### Working API Endpoints
- `GET /api/handbook/proposals` - Lists proposal branches
- `POST /api/handbook/proposals` - Creates proposal branch
- `POST /api/handbook/proposals/{branch_name}/approve` - Adds approval

### Git Branch Format
- Branch name: `proposals/{author}/{timestamp}-{description}`
- Example: `proposals/Fredrik/1751054070-update-handbook-docs-test-md`

### Approval Tracking
- Approval files: `.approval.{username}` (empty files)
- Auto-merge threshold: 2 approvals
- Merge commit message: `"Merge proposal: {branch_name}\n\nApproved by: {approver_list}"`

### Server Configuration
- Development server: `ruby test_handbook_server.rb` (port 3001)
- Routing pattern: `"/api/handbook/**"` (supports deep paths)
- SSL: Conditional based on `ENV['RACK_ENV']` 