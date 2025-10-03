#!/bin/bash
# Fix git permissions for shared repository access between fredrik and kimonokittens users
# Run with: sudo bash deployment/scripts/fix_git_permissions.sh

set -e  # Exit on any error

REPO_PATH="/home/kimonokittens/Projects/kimonokittens"
GROUP_NAME="kimonokittens"

echo "🔧 Setting up shared git repository permissions..."

# 1. Verify group exists
if ! getent group "$GROUP_NAME" > /dev/null; then
    echo "❌ Error: Group $GROUP_NAME does not exist!"
    exit 1
fi
echo "✓ Using existing group: $GROUP_NAME"

# 2. Add fredrik user to kimonokittens group
echo "Adding fredrik to $GROUP_NAME group..."
usermod -a -G "$GROUP_NAME" fredrik

# 3. Configure git shared repository
echo "Configuring git shared repository..."
cd "$REPO_PATH"
sudo -u kimonokittens git config core.sharedRepository group

# 4. Fix ownership and permissions
echo "Fixing .git directory ownership and permissions..."
chgrp -R "$GROUP_NAME" "$REPO_PATH/.git"
chmod -R g+w "$REPO_PATH/.git"
chmod -R g+s "$REPO_PATH/.git"  # setgid - new files inherit group

# 5. Fix any fredrik-owned git objects
echo "Fixing ownership of all git objects..."
find "$REPO_PATH/.git/objects" -type f -user fredrik -exec chgrp "$GROUP_NAME" {} \;
find "$REPO_PATH/.git/objects" -type f -user fredrik -exec chmod g+w {} \;
find "$REPO_PATH/.git/objects" -type d -user fredrik -exec chgrp "$GROUP_NAME" {} \;
find "$REPO_PATH/.git/objects" -type d -user fredrik -exec chmod g+ws {} \;

# 6. Verify configuration
echo ""
echo "✅ Configuration complete!"
echo ""
echo "Git config:"
sudo -u kimonokittens git -C "$REPO_PATH" config --get core.sharedRepository
echo ""
echo "Group members:"
getent group "$GROUP_NAME"
echo ""
echo "⚠️  IMPORTANT: Log out and back in for group membership to take effect!"
echo ""
echo "Test with:"
echo "  sudo -u kimonokittens git -C $REPO_PATH pull origin master"
