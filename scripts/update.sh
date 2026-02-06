#!/usr/bin/env bash

# Update upstream ML4W dotfiles to a new tag
# Usage: ./update.sh <TAG>

if [ $# -eq 0 ]; then
    echo "Error: TAG parameter is required"
    echo "Usage: $0 <TAG>"
    echo "Example: $0 2.9.9.6"
    exit 1
fi

TAG="$1"

echo "Updating upstream to tag: $TAG"

# Navigate to upstream directory
cd upstream || exit 1

# Fetch tags from remote
git fetch --tags

# Checkout the specified tag
git checkout "$TAG" || exit 1

# Go back to project root
cd ..

# Add upstream changes
git add upstream

# Commit the changes
git commit -m "update upstream to $TAG"

echo "Successfully updated upstream to $TAG"
