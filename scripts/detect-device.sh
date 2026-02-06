#!/bin/bash
# Auto-detect device by hostname

case $(hostname) in
  panda) echo "laptop" ;;
  falcon) echo "desktop" ;;
  *) echo "desktop" ;;  # fallback
esac
