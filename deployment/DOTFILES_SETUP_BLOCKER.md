# 🚨 CRITICAL BLOCKER: Dotfiles Setup Required

## 🎯 **Problem Statement**

The Dell Optiplex deployment is ready, but we're missing the **global Claude configuration** from the Mac Mini M2 that contains essential project-wide instructions.

## 🔍 **Specific Issues**

### **1. Missing Global CLAUDE.md**
- **Location**: Should be in global dotfiles repository
- **Content**: Project-wide instructions and patterns
- **Problem**: Each machine has isolated Claude config

### **2. rbenv Claude Code Compatibility**
- **Issue**: Claude Code Bash tool doesn't load shell functions
- **Impact**: `rbenv` command fails, requires direct binary paths
- **Workaround**: Must use `~/.rbenv/bin/rbenv exec` instead of `rbenv`

### **3. Development Environment Inconsistency**
- **Mac Mini M2**: Has optimized Claude config and global instructions
- **Dell Optiplex**: Missing these configurations
- **Result**: Different behavior across machines

## 📋 **Required Actions**

### **Immediate (Blocks Production)**
1. **Locate dotfiles repository** from Mac Mini M2
2. **Extract global CLAUDE.md** with project instructions
3. **Add rbenv Claude Code section** to global config
4. **Sync to Dell Optiplex**

### **Long-term (Prevents Future Issues)**
1. **Create dotfiles repository** if none exists
2. **Symlink strategy** for `.zshrc`, `.claude/`, etc.
3. **Bootstrap script** for machine setup
4. **Documentation** of dotfiles structure

## 🔧 **Technical Requirements**

### **Global CLAUDE.md Should Include**
```markdown
## Claude Code & rbenv Compatibility

Claude Code's Bash tool doesn't load shell functions. For rbenv:

### ❌ Won't Work
```bash
rbenv --version
rbenv exec ruby --version
```

### ✅ Use Instead
```bash
~/.rbenv/bin/rbenv --version
~/.rbenv/bin/rbenv exec ruby --version
RBENV_ROOT=~/.rbenv ~/.rbenv/bin/rbenv exec ruby --version
```

### Project-Specific Ruby Setup
```bash
# Set Ruby version for project
~/.rbenv/bin/rbenv local 3.3.8

# Install dependencies
~/.rbenv/bin/rbenv exec bundle install
```
```

### **Dotfiles Structure**
```
dotfiles/
├── .zshrc (symlinked to ~/.zshrc)
├── .claude/
│   ├── settings.json
│   └── global_CLAUDE.md
├── bootstrap.sh
└── README.md
```

## 🚀 **Implementation Options**

### **Option A: Quick Sync (Immediate)**
1. SSH to Mac Mini M2
2. Copy global Claude config manually
3. Apply to Dell Optiplex
4. Document locations for future

### **Option B: Proper Dotfiles (Better)**
1. Create dotfiles repository
2. Add all configuration files
3. Symlink setup script
4. Deploy to both machines

### **Option C: Hybrid Approach**
1. Quick sync for immediate deployment
2. Proper dotfiles setup afterward
3. Migrate existing configs to repository

## ⚠️ **Impact Assessment**

### **Without Dotfiles Fix**
- ❌ Inconsistent Claude Code behavior
- ❌ Manual rbenv path management
- ❌ Repeated configuration issues
- ❌ No shared project knowledge

### **With Dotfiles Fix**
- ✅ Consistent Claude Code experience
- ✅ Automatic rbenv compatibility
- ✅ Shared configuration across machines
- ✅ Faster onboarding for new environments

## 🎯 **Recommendation**

**Start with Option A (Quick Sync)** to unblock production deployment, then implement Option B (Proper Dotfiles) for long-term maintainability.

**Priority**: HIGH - This affects all future Claude Code sessions and development workflow.

---

**Next Steps**: Determine if Mac Mini M2 has existing dotfiles setup or if we need to create from scratch.