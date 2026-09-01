#!/bin/bash
# Auto-detect device by hostname

case $(hostname) in
  panda) echo "laptop" ;;
  falcon) echo "desktop" ;;
  aardwolf) echo "server" ;;
  *) echo "desktop" ;;  # fallback
esac
