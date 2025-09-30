#!/bin/bash
# Script to convert all handler files from Agoo to Ruby Logger

echo "Converting all handler files from Agoo to Ruby Logger..."

# List of handler files that need conversion
HANDLERS=(
  "handlers/rent_calculator_handler.rb"
  "handlers/handbook_handler.rb"
  "handlers/auth_handler.rb"
  "handlers/bank_buster_handler.rb"
  "handlers/todos_handler.rb"
)

# Function to convert a file
convert_file() {
  local file="$1"
  echo "Converting $file..."

  # Replace require 'agoo' with require 'logger'
  sed -i "s/require 'agoo'/require 'logger'/" "$file"

  # Replace Agoo::Log calls with @logger calls
  sed -i 's/Agoo::Log\.info/@logger.info/' "$file"
  sed -i 's/Agoo::Log\.warn/@logger.warn/' "$file"
  sed -i 's/Agoo::Log\.error/@logger.error/' "$file"
  sed -i 's/Agoo::Log\.debug/@logger.debug/' "$file"

  # Add logger initialization to initialize method (if class doesn't have one, this won't work perfectly)
  # We'll need to check each file individually for proper initialization
}

# Convert each handler file
for handler in "${HANDLERS[@]}"; do
  if [ -f "$handler" ]; then
    convert_file "$handler"
    echo "✅ Converted $handler"
  else
    echo "⚠️ File not found: $handler"
  fi
done

echo ""
echo "⚠️ IMPORTANT: You need to manually add logger initialization to each class!"
echo "Add this to each class's initialize method:"
echo "  @logger = Logger.new(STDOUT)"
echo "  @logger.level = Logger::INFO"
echo ""
echo "Files that need manual logger initialization:"
for handler in "${HANDLERS[@]}"; do
  if [ -f "$handler" ]; then
    echo "  - $handler"
  fi
done